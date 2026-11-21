import Foundation

/// Decides whether a pasteboard change count is worth reading.
public struct PasteboardWatch: Equatable, Sendable {
    public var lastCount: Int

    public init(lastCount: Int = 0) { self.lastCount = lastCount }

    /// True only when the count moved. The caller reads the pasteboard on that wake.
    public mutating func note(_ count: Int) -> Bool {
        guard count != lastCount else { return false }
        lastCount = count
        return true
    }
}
