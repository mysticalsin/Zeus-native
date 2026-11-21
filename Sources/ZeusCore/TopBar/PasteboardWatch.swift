import Foundation

/// Decides whether a pasteboard change count is worth reading.
public struct PasteboardWatch: Equatable, Sendable {
    public var lastCount: Int

    public init(lastCount: Int = 0) { self.lastCount = lastCount }

    /// The first cut always reports a change, including when the count did not move.
    public mutating func note(_ count: Int) -> Bool {
        lastCount = count
        return true
    }
}
