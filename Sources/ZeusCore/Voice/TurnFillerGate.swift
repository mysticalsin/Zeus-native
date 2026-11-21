import Foundation

/// Lets one filler line through per turn, however many races the turn runs.
public struct TurnFillerGate: Sendable {
    private var taken = false
    private var suppressed = false

    public init() {}

    /// The turn's first move is a tool or a pointer. A preamble must not follow it.
    public mutating func noteToolOrPointer() { suppressed = true }

    /// True the first time only, and never after a tool or pointer was noted.
    public mutating func take() -> Bool {
        guard !taken, !suppressed else { return false }
        taken = true
        return true
    }
}
