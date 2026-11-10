import AppKit
import CoreAudio
import ZeusCore

/// Observes volume (CoreAudio), brightness and keyboard backlight (polling). Key monitors stay an accelerator only.
@MainActor
final class SystemHUDMonitor {
    private weak var model: TopBarModel?
    private var pollTimer: Timer?
    private var lastBrightness: Double?
    private var lastKeyboard: Double?
    private var lastPoll = Date.distantPast
    private var lastValueChange = Date.distantPast
    private var volumeCoalescer = SystemHUDCoalescer()
    private var eventTap: SystemHUDEventTap?

    init(model: TopBarModel) {
        self.model = model
    }

    func start(volumeDevice: @escaping () -> AudioObjectID, currentVolume: @escaping () -> Float32?) {
        // H1: read the current hardware state once, up front, so the very first poll/event never
        // itself presents a HUD -- only a real change after this seed should.
        if let volume = currentVolume() { volumeCoalescer.seed(value: Double(volume), muted: false) }
        lastBrightness = DisplayBrightness.main()
        lastKeyboard = KeyboardBacklight.level()
        eventTap = SystemHUDEventTap(
            volumeDevice: volumeDevice,
            currentVolume: currentVolume,
            onChange: { [weak self] in self?.noteExternalChange() }
        )
        refreshEventTap()
        pollTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
        AccessibilityGate.whenTrusted { [weak self] in self?.refreshEventTap() }
    }

    func refreshEventTap() {
        let replace = SystemHUDSettings.replaceSystemEnabled { SettingsStore.shared.bool($0) }
        eventTap?.update(enabled: replace && AccessibilityGate.trusted)
    }

    func volumeChanged(volume: Float, muted: Bool) {
        guard SystemHUDSettings.isEnabled(.volume, bool: SettingsStore.shared.bool) else { return }
        if muted, !SystemHUDSettings.muteEffectsEnabled(bool: SettingsStore.shared.bool) { return }
        let value = Double(volume)
        guard volumeCoalescer.accept(value: value, muted: muted) else { return }
        present(.volume, value: value, muted: muted)
    }

    func brightnessAccelerator() {
        guard let level = DisplayBrightness.main() else { return }
        lastBrightness = level
        present(.brightness, value: level, muted: false)
    }

    private func poll() {
        let now = Date()
        let interval: TimeInterval = now.timeIntervalSince(lastValueChange) < 2 ? 0.1 : 0.5
        guard now.timeIntervalSince(lastPoll) >= interval else { return }
        lastPoll = now
        if SystemHUDSettings.isEnabled(.brightness, bool: SettingsStore.shared.bool), let level = DisplayBrightness.main() {
            if lastBrightness.map({ SystemHUDMath.shouldReport(previous: $0, next: level) }) ?? true {
                lastBrightness = level
                present(.brightness, value: level, muted: false)
            }
        }
        if SystemHUDSettings.isEnabled(.keyboardBacklight, bool: SettingsStore.shared.bool), let level = KeyboardBacklight.level() {
            if lastKeyboard.map({ SystemHUDMath.shouldReport(previous: $0, next: level) }) ?? true {
                lastKeyboard = level
                present(.keyboardBacklight, value: level, muted: false)
            }
        }
    }

    private func noteExternalChange() {
        lastValueChange = Date()
    }

    private func present(_ kind: SystemHUDKind, value: Double, muted: Bool) {
        lastValueChange = Date()
        model?.presentSystemHUD(kind, value: value, muted: muted)
    }
}
