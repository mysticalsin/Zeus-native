import Foundation

/// What the top bar does with a lone Shift hold.
///
/// Key-up is one transition. `ShiftPeekGate.release()` clears the peek, so a later hold can arm
/// the crest again. The crest that already started keeps the fade drawn for `NotchLightKind.shiftCrest`.
public enum ShiftPeekPolicy {
    public enum Effect: Equatable, Sendable {
        case scheduleCheck
        case cancelPending
        case showCrest
        /// Leave the crest `showCrest` started. Its duration and fade stay as they are.
        case fadeExistingCrest
    }

    /// Same wait the hold used before: half a second, plus a short slack so the check sees it.
    public static let checkAfter: TimeInterval = 0.52

    public static func shiftDown(_ gate: inout ShiftPeekGate, at now: Date) -> [Effect] {
        gate.shift(down: true, at: now)
        return [.scheduleCheck]
    }

    /// `revealed` is what `ShiftPeekGate.release()` just returned.
    public static func shiftedUp(revealed: Bool) -> [Effect] {
        revealed ? [.cancelPending, .fadeExistingCrest] : [.cancelPending]
    }

    public static func otherKey(_ gate: inout ShiftPeekGate) -> [Effect] {
        gate.otherKey()
        return [.cancelPending]
    }

    public static func checkDue(_ gate: inout ShiftPeekGate, at now: Date) -> [Effect] {
        gate.fire(at: now) ? [.showCrest] : []
    }
}
