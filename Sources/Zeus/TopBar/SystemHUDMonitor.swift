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
    private var displaysAsleep = false
    private var observers: [NSObjectProtocol] = []
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
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysAsleep = true; self?.schedulePoll() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaysAsleep = false
                self?.lastValueChange = Date() // a short burst: brightness often changes on wake
                self?.schedulePoll()
            }
        })
        // Turning a brightness or keyboard HUD on later starts the read; while a timer runs this does nothing.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.pollTimer == nil { self?.schedulePoll() } }
        })
        schedulePoll()
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
        schedulePoll()
    }

    /// One timer at a time, re-armed after every read: fast right after a change, slow otherwise, and
    /// none while no brightness or keyboard HUD is on or the displays sleep.
    private func schedulePoll() {
        pollTimer?.invalidate()
        pollTimer = nil
        let store = SettingsStore.shared
        guard SystemHUDPollPolicy.shouldPoll(
            brightnessEnabled: SystemHUDSettings.isEnabled(.brightness, bool: store.bool),
            keyboardBacklightEnabled: SystemHUDSettings.isEnabled(.keyboardBacklight, bool: store.bool),
            displaysAsleep: displaysAsleep) else { return }
        let interval = SystemHUDPollPolicy.interval(sinceLastChange: Date().timeIntervalSince(lastValueChange))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
                self?.schedulePoll()
            }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
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
        schedulePoll()
    }

    private func present(_ kind: SystemHUDKind, value: Double, muted: Bool) {
        lastValueChange = Date()
        model?.presentSystemHUD(kind, value: value, muted: muted)
    }
}
