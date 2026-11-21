import Foundation

/// One speak. A later speak gets a new id and must not clear an earlier cancel.
public final class UtteranceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var next: UInt64 = 0
    private var cancelled: Set<UInt64> = []
    private var active: UInt64?

    public init() {}

    public func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        // Red: a new utterance wipes every cancel, so stop() loses the line that was in flight.
        cancelled.removeAll()
        next += 1
        active = next
        return next
    }

    public func cancelActive() {
        lock.lock()
        defer { lock.unlock() }
        if let active { cancelled.insert(active) }
    }

    public func cancel(_ id: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        cancelled.insert(id)
        if active == id { active = nil }
    }

    public func isCancelled(_ id: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled.contains(id)
    }
}
