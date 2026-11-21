import Foundation

/// Outstanding replies. `failOutstanding` finishes every open id exactly once.
public struct ReplyLedger: Equatable, Sendable {
    public private(set) var openIDs: Set<Int> = []
    public private(set) var finished: Set<Int> = []
    public private(set) var released = false

    public init() {}

    public mutating func open(_ id: Int) -> Bool {
        if released || finished.contains(id) || openIDs.contains(id) { return false }
        openIDs.insert(id)
        return true
    }

    public mutating func finish(_ id: Int) -> Bool {
        guard openIDs.remove(id) != nil else { return false }
        finished.insert(id)
        return true
    }

    public mutating func failOutstanding() -> Set<Int> {
        // Red: release drops the ids without reporting them, so the waiters never resume.
        openIDs = []
        released = true
        return []
    }
}

/// Calls `failOutstanding` when the owner is released.
public final class ReplyDrop: @unchecked Sendable {
    private let lock = NSLock()
    private var ledger = ReplyLedger()
    public var onDrop: (@Sendable (Set<Int>) -> Void)?

    public init() {}

    public func open(_ id: Int) -> Bool { lock.withLock { ledger.open(id) } }

    public func finish(_ id: Int) -> Bool { lock.withLock { ledger.finish(id) } }

    deinit {
        let pending = lock.withLock { ledger.failOutstanding() }
        onDrop?(pending)
    }
}
