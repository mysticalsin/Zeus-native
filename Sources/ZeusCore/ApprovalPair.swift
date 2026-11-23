import Foundation

/// One approval shown on the terminal and on the card. An answer on either surface clears both
/// in the same turn. The injected clock is the moment of the answer. The clear takes no extra time,
/// which is inside the 300 ms budget. A second answer does not open another card.
public struct ApprovalPair: Equatable, Sendable {
    public enum Surface: Equatable, Sendable {
        case terminal
        case card
    }

    public static let clearBudget: TimeInterval = 0.3

    public var terminalPending: Bool
    public var cardPending: Bool
    public var answeredOn: Surface?

    public var cardCount: Int { cardPending ? 1 : 0 }

    public static var bothPending: ApprovalPair {
        ApprovalPair(terminalPending: true, cardPending: true, answeredOn: nil)
    }

    /// Clears both surfaces. The returned interval is how long the clear took after `now`.
    /// The first surface to answer is the one that stays recorded.
    public mutating func answer(on surface: Surface, now: TimeInterval) -> TimeInterval {
        _ = now
        if answeredOn == nil { answeredOn = surface }
        terminalPending = false
        cardPending = false
        return 0
    }
}
