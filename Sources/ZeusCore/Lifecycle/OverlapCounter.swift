/// A busy flag that survives overlapping operations.
///
/// `busy = true; await work; busy = false` is wrong when a second call starts before the first ends:
/// the first to finish clears the flag while the other is still running, and the buttons that disable
/// themselves on it come back too early. Each operation now counts itself in and out, and the flag is
/// "at least one is running".
public struct OverlapCounter: Equatable, Sendable {
    public private(set) var running = 0

    public init() {}

    public var isActive: Bool { running > 0 }

    public mutating func begin() { running += 1 }

    /// Never goes below zero, so an extra `end` cannot hide the next operation.
    public mutating func end() { running = max(0, running - 1) }
}
