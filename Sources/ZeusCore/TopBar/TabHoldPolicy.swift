import Foundation

/// Lone Tab, held with no modifier, reveals the tab strip and keeps it until the key comes up.
///
/// The gate already decided the timing. This is the stream of key events the top bar feeds it:
/// Tab down, a repeat, a modifier, any other key, the check, and Tab up. Tab is never consumed.
/// Revealing and fading use the panel the strip already lives in. Nothing new is drawn.
public enum TabHoldPolicy {
    /// ANSI Tab. The monitor compares key codes to this and still forwards the keystroke.
    public static let tabKeyCode: UInt16 = 48
    /// The gate's 0.4 s hold, plus a short slack so the check sees it.
    public static let checkAfter: TimeInterval = 0.42

    public enum Effect: Equatable, Sendable {
        case scheduleCheck
        case cancelPending
        case revealStrip
        case fadeStrip
    }

    public static func tabDown(_ gate: inout TabHoldGate, at now: Date, modifiersHeld: Bool, isRepeat: Bool) -> [Effect] {
        if isRepeat { return cancel(&gate) }
        gate.tabDown(at: now, modifiersHeld: modifiersHeld)
        guard !modifiersHeld else { return [] }
        return [.scheduleCheck]
    }

    public static func otherKey(_ gate: inout TabHoldGate) -> [Effect] {
        cancel(&gate)
    }

    public static func flagsChanged(_ gate: inout TabHoldGate, modifiersHeld: Bool) -> [Effect] {
        guard modifiersHeld else { return [] }
        let holding = gate.downAt != nil && !gate.cancelled
        guard holding || gate.revealed else { return [] }
        return cancel(&gate)
    }

    public static func checkDue(_ gate: inout TabHoldGate, at now: Date) -> [Effect] {
        gate.fire(at: now) ? [.revealStrip] : []
    }

    public static func tabUp(_ gate: inout TabHoldGate) -> [Effect] {
        let fade = gate.tabUp()
        return fade ? [.cancelPending, .fadeStrip] : [.cancelPending]
    }

    private static func cancel(_ gate: inout TabHoldGate) -> [Effect] {
        let fade = gate.revealed
        gate.otherKey()
        return fade ? [.cancelPending, .fadeStrip] : [.cancelPending]
    }
}
