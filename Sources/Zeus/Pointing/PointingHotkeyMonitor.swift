import AppKit
import ZeusCore

/// The pointing settings (`Settings > Assistant > Desktop pointing`). Everything is off until the
/// owner turns it on, and the screenshot upload has its own separate consent.
enum PointingSettings {
    static var enabled: Bool { FeatureSettings.bool("pointing.enabled", default: false) }
    static var sendScreenshot: Bool { FeatureSettings.bool("pointing.sendScreenshot", default: false) }
    /// Double-tap Control opens a typed-question box. Off by default: macOS Dictation can also use
    /// "Press Control key twice", and both would fire.
    static var textEntry: Bool { FeatureSettings.bool("pointing.textEntry", default: false) }
    static var dictationFnControl: Bool { FeatureSettings.bool("pointing.dictationFnControl", default: false) }
    static var providerChoice: PointingProviderChoice {
        PointingProviderChoice(setting: FeatureSettings.string("pointing.provider", default: "Auto"))
    }
    static let shortcutChoices: [String: Shortcut] = [
        "Control-Option": .controlOption, "Right Option": .rightOption, "Fn (Globe)": .function,
    ]
    static var shortcut: Shortcut {
        shortcutChoices[FeatureSettings.string("pointing.shortcut", default: "Control-Option")] ?? .controlOption
    }
}

/// Feeds the keyboard stream to `PointingKeyGesture` and reports what the hold did. It owns no
/// callbacks of its own: the tap lives in nonisolated code (`PointingEventTap`).
@MainActor
final class PointingHotkeyMonitor {
    enum Signal: Equatable { case began, ended, cancelled, escape, doubleTapControl, timedOut, blocked(String) }

    var onSignal: ((Signal) -> Void)?
    var shortcutProvider: () -> Shortcut = { PointingSettings.shortcut }
    var voiceOverProvider: () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }
    /// The modifiers the system reports right now, for the stuck-key watchdog.
    var liveModifiers: () -> ShortcutModifiers? = {
        ShortcutModifiers(NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
    }
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Called once when the keyboard cannot be observed (neither Accessibility nor Input Monitoring).
    var onUnavailable: (() -> Void)?

    private var gesture = PointingKeyGesture()
    private var tap: PointingEventTap?
    private var announcedBlock = false
    private var watchdog: Timer?
    private(set) var isRunning = false

    /// Idempotent. Waits for the owner's own permission grant; never prompts.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        KeyListenAccess.whenGranted { [weak self] in self?.startTap() }
    }

    func stop() {
        isRunning = false
        tap?.stop(); tap = nil
        stopWatchdog()
        gesture.reset()
    }

    /// Sleep, wake or a display change: drops a hold in progress. Nothing is sent.
    func interruptGesture() {
        _ = gesture.interrupt()
        stopWatchdog()
    }

    /// While a hold is active, a few times a second, compare the tracked keys with the live ones.
    private func startWatchdog() {
        stopWatchdog()
        watchdog = PointingTimers.repeating(every: 0.25) { [weak self] in self?.watchdogTick() }
    }

    private func stopWatchdog() { watchdog?.invalidate(); watchdog = nil }

    /// Also the entry point for tests.
    func watchdogTick() {
        guard let output = gesture.tick(at: now(), liveModifiers: liveModifiers()) else { return }
        stopWatchdog()
        if output == .holdTimedOut { onSignal?(.timedOut) }
    }

    private func startTap() {
        guard isRunning, tap == nil else { return }
        let created = PointingEventTap { [weak self] event, time in self?.feed(event, at: time) }
        guard created.start() else { onUnavailable?(); return }
        tap = created
    }

    /// One keyboard event. Also the entry point for tests.
    func feed(_ event: ShortcutEvent, at time: TimeInterval) {
        let wanted = shortcutProvider()
        if wanted != gesture.shortcut, !gesture.isActive { gesture.shortcut = wanted }
        let voiceOverOn = voiceOverProvider()
        let output = gesture.feed(event, at: time, voiceOverOn: voiceOverOn)
        if gesture.blockedByVoiceOver, !announcedBlock {
            announcedBlock = true
            onSignal?(.blocked("VoiceOver is using Control and Option. Choose another pointing key in Settings."))
        }
        // Announce once per VoiceOver session, not on every attempt: re-arm only when VoiceOver goes off.
        if !voiceOverOn { announcedBlock = false }
        switch output {
        case .began?: startWatchdog(); onSignal?(.began)
        case .ended?: stopWatchdog(); onSignal?(.ended)
        case .cancelled?: stopWatchdog(); onSignal?(.cancelled)
        case .holdTimedOut?: stopWatchdog(); onSignal?(.timedOut)
        case .escape?: onSignal?(.escape)
        case .doubleTapControl?: onSignal?(.doubleTapControl)
        case nil: break
        }
    }
}
