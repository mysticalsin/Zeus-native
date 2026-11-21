import Foundation

/// A capture may start again only after its stop has finished.
public struct CaptureStopGate: Equatable, Sendable {
    public private(set) var running = false
    public private(set) var stopOpen = false

    public init() {}

    public mutating func requestStop() {
        guard running || stopOpen else { return }
        running = false
        stopOpen = true
    }

    public mutating func stopFinished() {
        stopOpen = false
    }

    public mutating func start() -> Bool {
        guard !stopOpen else { return false }
        running = true
        return true
    }
}
