import AppKit
import Foundation
import Observation
import ZeusCore

/// The live audio level shared by the Waves tab and the closed-notch music light.
/// It does nothing (no tap, no timer, no FFT) unless `SpectrumGate.shouldRun` says so.
@MainActor
@Observable
final class AudioSpectrumService {
    static let shared = AudioSpectrumService()

    static let permissionKey = "audio.capturePermission"
    static let styleKey = "waves.style"
    static let sensitivityKey = "waves.sensitivity"
    static let liveKey = "lights.liveSpectrum"

    /// Smoothed band levels, 0...1. Read it from a TimelineView; it changes up to 60 times a second.
    private(set) var levels = [Float](repeating: 0, count: SpectrumMath.bandCount)
    /// Overall level, 0...1 (the mean of the lower bands, for the closed-notch wave).
    private(set) var overall: Float = 0
    private(set) var permission: AudioCapturePermission
    private(set) var lastError: String?
    private(set) var running = false

    @ObservationIgnored private var wavesVisible = false
    @ObservationIgnored private var musicPlaying = false
    @ObservationIgnored private var pipeline: SpectrumPipeline?
    @ObservationIgnored private let defaults: UserDefaults
    /// Set by a person's action (toggle on, open Waves, press Allow); consumed by the next start.
    @ObservationIgnored private var personAsked = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permission = AudioCapturePermission(rawValue: defaults.string(forKey: Self.permissionKey) ?? "") ?? .notAsked
    }

    private var closedSpectrumOn: Bool { SettingsStore.shared.bool(Self.liveKey) }

    // MARK: Inputs

    /// The Waves tab appeared or went away. Opening it is a person's request, so it may ask.
    func setWavesVisible(_ visible: Bool) {
        wavesVisible = visible
        if visible { personAsked = true }
        reconcile()
    }

    func setMusicPlaying(_ playing: Bool) {
        guard musicPlaying != playing else { return }
        musicPlaying = playing
        reconcile()
    }

    /// The Settings toggle changed. Turning it on is a person's request, so it may ask.
    func liveSpectrumChanged(on: Bool) {
        if on { personAsked = true }
        reconcile(forceOnce: on && permission == .notAsked) // ask now, not at some later song
    }

    /// The "Allow" button. The only other way (besides the toggle and the tab) to raise the macOS prompt.
    func allowPressed() {
        if permission == .refused { openSystemSettings(); return }
        personAsked = true
        // Run a short test even when nothing else wants audio, so the button does something.
        reconcile(forceOnce: true)
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") { NSWorkspace.shared.open(url) }
    }

    /// Drawn-from-nothing spectrum for snapshots.
    func seedForSnapshot(_ values: [Float]) {
        levels = values
        overall = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    // MARK: Run / stop

    private var shouldRun: Bool { SpectrumGate.shouldRun(wavesVisible: wavesVisible, closedSpectrumOn: closedSpectrumOn, musicPlaying: musicPlaying) }

    private func reconcile(forceOnce: Bool = false) {
        if TopBarStyle.isSnapshot { return }
        guard shouldRun || forceOnce else { stop(); return }
        switch SpectrumGate.decision(permission: permission, personAsked: personAsked) {
        case .capture: start(testOnly: forceOnce && !shouldRun)
        case .wait: stop()
        case .needsSettings: stop()
        }
    }

    private func start(testOnly: Bool) {
        if pipeline == nil {
            let new = SpectrumPipeline()
            do {
                try new.open()
            } catch {
                lastError = "\(error)"
                setPermission(.refused)
                stop()
                return
            }
            new.onFrame = { [weak self] levels, overall in
                Task { @MainActor in self?.receive(levels, overall) }
            }
            pipeline = new
            lastError = nil
            setPermission(.allowed)
        }
        personAsked = false
        guard !testOnly else { stop(); return }
        pipeline?.gain = SpectrumMath.gain(sensitivityPercent: SettingsStore.shared.double(Self.sensitivityKey))
        pipeline?.run(fps: SpectrumGate.framesPerSecond(wavesVisible: wavesVisible))
        running = true
    }

    private func receive(_ new: [Float], _ mean: Float) {
        guard running else { return }
        levels = new
        overall = mean
    }

    /// The sensitivity slider moved.
    func sensitivityChanged() {
        pipeline?.gain = SpectrumMath.gain(sensitivityPercent: SettingsStore.shared.double(Self.sensitivityKey))
    }

    private func stop() {
        pipeline?.close()
        pipeline = nil
        running = false
        if !levels.allSatisfy({ $0 == 0 }) {
            levels = [Float](repeating: 0, count: SpectrumMath.bandCount)
            overall = 0
        }
    }

    private func setPermission(_ value: AudioCapturePermission) {
        permission = value
        defaults.set(value.rawValue, forKey: Self.permissionKey)
    }
}
