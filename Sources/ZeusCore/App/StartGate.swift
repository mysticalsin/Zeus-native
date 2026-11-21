import Foundation

/// A launch `start` that must install its observers only once.
public struct StartGate: Equatable, Sendable {
    public private(set) var started = false

    public init() {}

    public mutating func start() -> Bool {
        // Red: every call installs another set of observers.
        return true
    }
}
