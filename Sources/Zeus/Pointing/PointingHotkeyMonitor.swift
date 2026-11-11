import AppKit
import ZeusCore

/// The pointing settings (`Settings > Assistant > Desktop pointing`). Pointing and drawing while held
/// are on from the first launch; the screenshot upload has its own separate consent and stays off.
enum PointingSettings {
    static var enabled: Bool { FeatureSettings.pointingEnabled() }
    static var drawWhileHeld: Bool { FeatureSettings.pointingDrawWhileHeld() }
    static var sendScreenshot: Bool { FeatureSettings.pointingSendScreenshot() }
    static var providerChoice: PointingProviderChoice {
        PointingProviderChoice(setting: FeatureSettings.string("pointing.provider", default: "Auto"))
    }
    static let shortcutChoices: [String: Shortcut] = [
        "Control-Option": .controlOption, "Right Option": .rightOption, "Fn (Globe)": .function,
    ]
    static func resolvedShortcut(defaults: UserDefaults = .standard) -> Shortcut {
        shortcutChoices[FeatureSettings.pointingShortcutName(defaults: defaults)] ?? .controlOption
    }
    static var shortcut: Shortcut { resolvedShortcut() }
}

/// Feeds the keyboard stream to `PointingKeyGesture` and reports what the hold did. It owns no
/// callbacks of its own: the tap lives in nonisolated code (`PointingEventTap`).
@MainActor
final class PointingHotkeyMonitor {
    enum Signal: Equatable { case began, ended, cancelled, escape, doubleTapControl, blocked(String) }

    var onSignal: ((Signal) -> Void)?
    var shortcutProvider: () -> Shortcut = { PointingSettings.shortcut }
    var voiceOverProvider: () -> Bool = { NSWorkspace.shared.isVoiceOverEnabled }
    /// Called once when the keyboard cannot be observed (neither Accessibility nor Input Monitoring).
    var onUnavailable: (() -> Void)?

    private var gesture = PointingKeyGesture()
    private var tap: PointingEventTap?
    private var announcedBlock = false
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
        gesture.reset()
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
        case .began?: onSignal?(.began)
        case .ended?: onSignal?(.ended)
        case .cancelled?: onSignal?(.cancelled)
        case .escape?: onSignal?(.escape)
        case .doubleTapControl?: onSignal?(.doubleTapControl)
        case nil: break
        }
    }
}
