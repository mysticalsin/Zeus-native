import Foundation

/// Shared waiting helpers for the socket and native host fixtures.
///
/// The hosted macOS runner has three cores, so the cooperative pool has three threads while thousands of tests start
/// at once. A waiter can be resumed seconds after its deadline, and a blocking socket call run in a detached task holds
/// a pool thread for its whole timeout. Waits therefore look at their condition once more after the deadline, use
/// bounds far above the happy path, and blocking calls run on their own threads.
enum PollingWait {
    /// Generous bound for something that normally takes milliseconds. A pass returns at once, so it costs nothing.
    static let eventBound: Duration = .seconds(20)

    /// True once `condition` holds. Gives up at `timeout` or when `giveUp` says so, and then checks one last time,
    /// because the waiter may only have been resumed after the deadline.
    static func until(timeout: Duration = eventBound,
                      giveUp: () -> Bool = { false },
                      pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(5)) },
                      _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if condition() { return true }
            try await pause()
        } while !giveUp() && ContinuousClock.now < deadline
        return condition()
    }

    /// Runs a blocking call on a dispatch thread so it never holds a cooperative pool thread.
    static func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// `blocking`, started now and awaited later.
    static func start<T: Sendable>(_ work: @escaping @Sendable () -> T) -> Pending<T> {
        let pending = Pending<T>()
        DispatchQueue.global(qos: .userInitiated).async { pending.finish(work()) }
        return pending
    }

    final class Pending<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: T?
        private var waiter: CheckedContinuation<T, Never>?

        fileprivate func finish(_ value: T) {
            let resume = lock.withLock { () -> CheckedContinuation<T, Never>? in
                if let waiter { self.waiter = nil; return waiter }
                result = value
                return nil
            }
            resume?.resume(returning: value)
        }

        var value: T {
            get async {
                await withCheckedContinuation { continuation in
                    let ready = lock.withLock { () -> T? in
                        if let result { return result }
                        waiter = continuation
                        return nil
                    }
                    if let ready { continuation.resume(returning: ready) }
                }
            }
        }
    }
}
