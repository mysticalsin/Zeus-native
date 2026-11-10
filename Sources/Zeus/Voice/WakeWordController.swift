import AppKit
import AVFoundation
import CoreAudio
import Observation
import Speech
import ZeusCore

/// "Hey Zeus": off until the user turns it on, on-device only. Decides when the listener may run
/// (`WakeGate`) and hands a heard request to the voice turn, exactly as if the talk key had been
/// pressed. macOS is asked for the microphone and speech recognition only when the user enables
/// it (`VoicePermissions`), never at launch; when refused it says so in the notch, with a button.
@MainActor
@Observable
final class WakeWordController {
    static let shared = WakeWordController()
    static let defaultsKey = "wake.enabled"

    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            if !TopBarStyle.isSnapshot { UserDefaults.standard.set(enabled, forKey: Self.defaultsKey) }
            if enabled, !TopBarStyle.isSnapshot { Task { await VoicePermissions.ensure(explicit: true); evaluate() } }
            evaluate()
        }
    }
    /// "Listening", "Paused: dictation", "Off"… for Settings.
    private(set) var status = "Off"
    private(set) var needsPermissions = false
    private(set) var listening = false

    @ObservationIgnored private weak var voice: VoiceTurnController?
    @ObservationIgnored private weak var topBar: TopBarModel?
    @ObservationIgnored private var listener: WakeWordListener?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenLocked = false
    @ObservationIgnored private var cooldownUntil = Date.distantPast
    @ObservationIgnored private var otherAppRecording = false
    @ObservationIgnored private var lastMicCheck = Date.distantPast
    @ObservationIgnored private var micCheckRunning = false
    @ObservationIgnored private var lastReason: String?
    @ObservationIgnored private var cpuMark: (ProcessEnergy, Date)?
    @ObservationIgnored private var retryStartAt = Date.distantPast
    @ObservationIgnored private var lastGate = WakeGate()
    @ObservationIgnored private var lastLoggedStatus = ""
    /// The `zeus status` line: "listening", "paused (dictation)", "no permission", "off".
    var cliStatus: String { lastGate.statusLine(listening: listening) }
    /// True while the talk key is held (set by the hotkey), so the two never share the mic.
    @ObservationIgnored var talkKeyHeld = false { didSet { evaluate() } }

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? false
    }

    func start(voice: VoiceTurnController, topBar: TopBarModel) {
        guard !TopBarStyle.isSnapshot else { return }
        self.voice = voice
        self.topBar = topBar
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WakeWordController.shared.setLocked(true) }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WakeWordController.shared.setLocked(false) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, locked) in [(NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false),
                               (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { WakeWordController.shared.setLocked(locked) }
            })
        }
        // A few booleans and, every 2 s, one Core Audio query: cheap enough to poll.
        timer = Timer.scheduledTimer(withTimeInterval: TickRules.wakeGateSeconds, repeats: true) { _ in // gate checks (mic in use, lock)
            MainActor.assumeIsolated { WakeWordController.shared.evaluate() }
        }
        evaluate()
        // Launch never asks macOS for anything: permissions are requested only from the explicit
        // enable action (`enabled.didSet`) or the talk key. Just record the current state.
        VoiceLog.log("launch", "wake word \(enabled ? "on" : "off"), voice access \(VoicePermissions.access)")
    }

    /// Assigns only on change, so an open Settings page isn't redrawn by the 0.5 s poll.
    private func setStatus(_ text: String) {
        if status != text { status = text }
    }

    private func setLocked(_ locked: Bool) {
        screenLocked = locked
        evaluate()
    }

    func evaluate() {
        let gate = currentGate()
        lastGate = gate
        let missing = !(gate.micAllowed && gate.speechAllowed)
        if missing != needsPermissions { needsPermissions = missing }
        if let reason = gate.pauseReason {
            if listener != nil { stopListener() }
            setStatus(reason == "off" ? "Off" : needsPermissions ? "Needs permissions" : "Paused: \(reason)")
            if reason != lastReason, listener == nil, reason != "off" { VoiceLog.log("wake", "paused (\(reason))") }
            lastReason = reason
        } else if listener == nil, Date() >= retryStartAt {
            startListener()
            lastReason = nil
        }
        logCPUIfDue()
    }

    private func currentGate() -> WakeGate {
        var gate = WakeGate()
        gate.enabled = enabled
        gate.micAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        gate.speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        gate.screenLocked = screenLocked
        gate.talkKeyActive = talkKeyHeld || (voice?.isListening ?? false)
        gate.dictating = (topBar?.isDictating ?? false) || TodoController.shared.listening
            || (topBar.map { $0.prompterActive && $0.roll.voiceFollow } ?? false)
        gate.speaking = voice?.isSpeaking ?? false
        gate.turnRunning = voice?.turnRunning ?? false
        gate.cooldown = Date() < cooldownUntil
        // Core Audio is asked off the main thread (it walks every audio process), and only while the
        // wake word is on: nobody reads the answer otherwise.
        if enabled, !micCheckRunning, Date().timeIntervalSince(lastMicCheck) > TickRules.micCheckSeconds {
            lastMicCheck = Date()
            micCheckRunning = true
            Task.detached(priority: .utility) {
                let recording = MicUsage.otherAppRecording()
                await MainActor.run {
                    let controller = WakeWordController.shared
                    controller.micCheckRunning = false
                    guard controller.otherAppRecording != recording else { return }
                    controller.otherAppRecording = recording
                    controller.evaluate()
                }
            }
        }
        // Debug-only escape hatch for QA: a build or test environment where Core Audio keeps
        // reporting a conflict that isn't real can force it off instead of never hearing "Hey Zeus".
        // Release builds always keep the call guard, whatever a stored setting or imported file says.
        #if DEBUG
        gate.otherAppRecording = otherAppRecording && !SettingsStore.shared.bool("wake.ignoreMicConflicts")
        #else
        gate.otherAppRecording = otherAppRecording
        #endif
        return gate
    }

    private func startListener() {
        guard let voice else { return }
        let listener = WakeWordListener(localeIdentifier: voice.speechLocale)
        guard listener.onDeviceSupported else {
            setStatus("Paused: on-device recognition isn't available for \(voice.speechLocale)")
            if lastLoggedStatus != status { lastLoggedStatus = status; VoiceLog.log("error", status) }
            retryStartAt = Date().addingTimeInterval(30)
            return
        }
        listener.onWake = { request in
            Task { @MainActor in WakeWordController.shared.handleWakeFromListener(request) }
        }
        do {
            try listener.start()
            self.listener = listener
            if !listening { listening = true }
            setStatus("Listening")
            cpuMark = (ProcessEnergy.sample(), Date())
            VoiceLog.log("wake", "listening on this Mac (recogniser locale \(listener.localeIdentifier))")
        } catch {
            setStatus("Paused: the microphone didn't start")
            VoiceLog.log("error", "wake mic start failed: \(error.localizedDescription)")
            retryStartAt = Date().addingTimeInterval(10)
        }
    }

    private func stopListener() {
        listener?.stop()
        listener = nil
        if listening { listening = false }
    }

    private func handleWakeFromListener(_ request: String) {
        guard listener != nil else { return }
        woke(request)
    }

    private func woke(_ request: String) {
        stopListener()
        cooldownUntil = Date().addingTimeInterval(1.5)
        if request.isEmpty {
            VoiceLog.log("wake", "heard, request (none yet)")
        } else {
            VoiceLog.logContent("wake", request, prefix: "heard, request ")
        }
        voice?.wakeTurn(request: request)
        evaluate()
    }

    /// Debug/E2E (`zeus debug dictate-file`): feed a rendered WAV through the wake listener (no
    /// microphone, no dictation pause). Returns "ok" when the wake phrase fired; nil to fall through
    /// to Murmur dictation for clips that are not a wake phrase.
    func injectWakeFile(_ url: URL) async -> String? {
        guard enabled, let voice else { return nil }
        stopListener()
        VoiceLog.log("inject", "wake probe \(url.lastPathComponent)")
        guard let request = await WakeWordFilePlayer.play(url: url, localeIdentifier: voice.speechLocale, onWake: { _ in }) else {
            evaluate()
            return nil
        }
        woke(request)
        for _ in 0..<400 {
            if !voice.turnRunning, !voice.isListening { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        evaluate()
        return "ok"
    }

    /// Every 10 minutes while listening: process CPU and how much of the time the recogniser ran.
    private func logCPUIfDue() {
        guard let listener, let (mark, at) = cpuMark, Date().timeIntervalSince(at) >= 600 else { return }
        let now = ProcessEnergy.sample()
        let cpu = ProcessEnergy.cpuPercent(from: mark, to: now, over: Date().timeIntervalSince(at))
        let stats = listener.stats
        NSLog("[ZEUS] wake: Zeus process CPU %.1f%% over 10 min; recogniser ran %.0f%% of %.0f s of audio",
              cpu, stats.audio > 0 ? stats.recognizing / stats.audio * 100 : 0, stats.audio)
        cpuMark = (now, Date())
    }
}

/// Whether another app is recording from a microphone right now (a call, a voice memo), through
/// Core Audio's process objects (macOS 14.2+). Apple's own background daemons are ignored, except
/// the ones that carry calls.
enum MicUsage {
    static func otherAppRecording() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        for process in processes {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid != own else { continue }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let id = AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr
                ? (bundle?.takeRetainedValue() as String?) ?? "" : ""
            if MicConflict.counts(bundleID: id, pid: pid, ownPID: own) { return true }
        }
        return false
    }
}
