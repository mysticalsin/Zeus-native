import Foundation

/// The pointing talk key. Pure: feed it the keyboard stream, it says when a hold began, ended,
/// or was spoiled. It owns no monitor, so the same logic serves a CGEvent tap and the tests.
///
/// Rules: the chord starts the moment it is held exactly. Any other key or modifier joining
/// cancels the turn (the "spoil" rule), so Control+Option+Space (Chat) and other chords that
/// share the modifiers keep working. A cancelled hold cannot restart until every modifier is up.
public struct PointingKeyGesture: Sendable {
    public enum Output: Equatable, Sendable {
        case began
        case ended
        case cancelled
        /// Esc with no modifiers while no hold is active (interrupts speech).
        case escape
        /// Two quick lone Control taps. Detected only; Phase 1 does not act on it.
        case doubleTapControl
        /// The hold never reported a release: the live modifiers say the keys are up, or `maxHold` passed.
        /// The gesture has already resynced; the turn should end as if the keys were released.
        case holdTimedOut
    }

    public static let tapMaximum: TimeInterval = 0.30
    public static let doubleTapWindow: TimeInterval = 0.40
    /// A hold longer than this is a stuck modifier (the microphone stops at 90 s anyway).
    public static let maxHold: TimeInterval = 95

    public var shortcut: Shortcut
    public private(set) var isActive = false
    /// True while the chord is held but unusable (Control+Option with VoiceOver on).
    public private(set) var blockedByVoiceOver = false
    private var state = ShortcutState()
    private var waitForRelease = false
    private var activeSince: TimeInterval?
    private var controlDownAt: TimeInterval?
    private var controlTapClean = false
    private var lastControlTap: TimeInterval?

    public init(shortcut: Shortcut = .controlOption) { self.shortcut = shortcut }

    public mutating func feed(_ event: ShortcutEvent, at time: TimeInterval, voiceOverOn: Bool = false) -> Output? {
        state.apply(event)
        let tap = trackControlTap(event, at: time)
        let held = state.isHeld(shortcut, exact: true)

        if isActive {
            if held { return nil }
            isActive = false; activeSince = nil
            let released = state.modifiers.isSubset(of: shortcut.modifiers) && !state.spoiled && state.keysDown.isEmpty
            if released { return .ended }
            waitForRelease = true
            return .cancelled
        }
        if waitForRelease {
            if state.modifiers.isEmpty && state.keysDown.isEmpty { waitForRelease = false }
            return nil
        }
        if held {
            blockedByVoiceOver = voiceOverOn && shortcut == .controlOption
            if blockedByVoiceOver { return nil }
            isActive = true
            activeSince = time
            return .began
        }
        blockedByVoiceOver = false
        if case .keyDown(53, let mods) = event, mods.isEmpty { return .escape }
        return tap
    }

    public mutating func reset() { self = PointingKeyGesture(shortcut: shortcut) }

    /// Watchdog, called a few times a second while a hold is active. `liveModifiers` is what the
    /// system reports right now (nil when unknown). If they no longer include the chord, or the hold
    /// outlived `maxHold`, a release was missed: resync the tracked state and report `holdTimedOut`.
    public mutating func tick(at time: TimeInterval, liveModifiers: ShortcutModifiers?) -> Output? {
        guard isActive, let since = activeSince else { return nil }
        let released = liveModifiers.map { !$0.isSuperset(of: shortcut.modifiers) } ?? false
        guard released || time - since > Self.maxHold else { return nil }
        isActive = false; activeSince = nil
        state.reset(); controlDownAt = nil; controlTapClean = false
        // Until the system shows every key up, a new hold cannot start.
        waitForRelease = !(liveModifiers?.isEmpty ?? false)
        return .holdTimedOut
    }

    /// Sleep, wake or a display change: a hold in progress is cancelled and cannot restart until every
    /// modifier is up. Nothing is sent. Returns `.cancelled` only when a hold was active.
    public mutating func interrupt() -> Output? {
        let wasActive = isActive
        isActive = false; activeSince = nil
        state.reset(); controlDownAt = nil; controlTapClean = false; lastControlTap = nil
        waitForRelease = wasActive
        return wasActive ? .cancelled : nil
    }

    private mutating func trackControlTap(_ event: ShortcutEvent, at time: TimeInterval) -> Output? {
        switch event {
        case .keyDown:
            controlTapClean = false
        case .flags:
            let mods = state.modifiers
            if mods == [.control], controlDownAt == nil {
                controlDownAt = time; controlTapClean = true
            } else if mods.isEmpty, let down = controlDownAt {
                defer { controlDownAt = nil; controlTapClean = false }
                guard controlTapClean, time - down <= Self.tapMaximum else { lastControlTap = nil; return nil }
                if let last = lastControlTap, time - last <= Self.doubleTapWindow {
                    lastControlTap = nil
                    return .doubleTapControl
                }
                lastControlTap = time
            } else if mods != [.control] {
                controlTapClean = false
            }
        case .keyUp: break
        }
        return nil
    }
}
