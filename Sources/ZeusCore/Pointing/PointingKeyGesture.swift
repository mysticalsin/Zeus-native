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
    }

    public static let tapMaximum: TimeInterval = 0.30
    public static let doubleTapWindow: TimeInterval = 0.40

    public var shortcut: Shortcut
    public private(set) var isActive = false
    /// True while the chord is held but unusable (Control+Option with VoiceOver on).
    public private(set) var blockedByVoiceOver = false
    private var state = ShortcutState()
    private var waitForRelease = false
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
            isActive = false
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
            return .began
        }
        blockedByVoiceOver = false
        if case .keyDown(53, let mods) = event, mods.isEmpty { return .escape }
        return tap
    }

    public mutating func reset() { self = PointingKeyGesture(shortcut: shortcut) }

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
