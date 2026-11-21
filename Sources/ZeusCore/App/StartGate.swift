import Foundation

/// A launch `start` that must install its observers only once.
public struct StartGate: Equatable, Sendable {
    public private(set) var started = false

    public init() {}

    public mutating func start() -> Bool {
        if started { return false }
        started = true
        return true
    }
}
