import Foundation

/// Lets one filler line through per turn, however many races the turn runs.
public struct TurnFillerGate: Sendable {
    private var taken = false

    public init() {}

    /// The turn's first move is a tool or a pointer. A preamble must not follow it.
    public mutating func noteToolOrPointer() {}

    /// True the first time only.
    public mutating func take() -> Bool {
        guard !taken else { return false }
        taken = true
        return true
    }
}
