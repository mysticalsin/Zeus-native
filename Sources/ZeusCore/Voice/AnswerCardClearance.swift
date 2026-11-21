import Foundation

/// Whether the answer card from an earlier turn may stay up.
/// A new question clears it. A show from the old generation cannot bring it back.
public struct AnswerCardClearance: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var visible = false

    public init() {}

    /// The generation later shows must match. The card from the previous generation goes.
    @discardableResult
    public mutating func questionStarted() -> UInt64 {
        generation &+= 1
        return generation
    }

    /// Shows the card for `generation` only.
    public mutating func show(generation: UInt64) -> Bool {
        visible = true
        return true
    }
}
