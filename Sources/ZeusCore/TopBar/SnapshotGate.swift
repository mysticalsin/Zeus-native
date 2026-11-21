import Foundation

/// A generation for an async fetch. Only the latest begin may write its result.
public struct SnapshotGate: Equatable, Sendable {
    public private(set) var generation: UInt64 = 0

    public init() {}

    public mutating func begin() -> UInt64 {
        generation += 1
        return generation
    }

    public func accepts(_ token: UInt64) -> Bool {
        token != 0 && token == generation
    }
}
