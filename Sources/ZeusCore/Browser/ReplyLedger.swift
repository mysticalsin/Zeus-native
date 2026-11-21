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
        let pending = openIDs
        finished.formUnion(pending)
        openIDs.removeAll()
        released = true
        return pending
    }
}

/// Resumes every stored continuation when the owner is released.
public final class ContinuationBag<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var ledger = ReplyLedger()
    private var continuations: [Int: CheckedContinuation<Success, Error>] = []

    public init() {}

    public var openCount: Int { lock.withLock { ledger.openIDs.count } }

    public func contains(_ id: Int) -> Bool { lock.withLock { ledger.openIDs.contains(id) } }

    public func store(_ id: Int, _ continuation: CheckedContinuation<Success, Error>, failure: Error) {
        let abandon = lock.withLock { () -> Bool in
            guard ledger.open(id) else { return true }
            continuations[id] = continuation
            return false
        }
        if abandon { continuation.resume(throwing: failure) }
    }

    @discardableResult
    public func resume(_ id: Int, with result: Result<Success, Error>) -> Bool {
        let continuation: CheckedContinuation<Success, Error>? = lock.withLock {
            guard ledger.finish(id) else { return nil }
            return continuations.removeValue(forKey: id)
        }
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }

    public func failAll(_ error: Error) {
        let pending: [CheckedContinuation<Success, Error>] = lock.withLock {
            ledger.failOutstanding().compactMap { continuations.removeValue(forKey: $0) }
        }
        for continuation in pending { continuation.resume(throwing: error) }
    }

    deinit { failAll(CancellationError()) }
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
