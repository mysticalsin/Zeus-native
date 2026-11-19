import Foundation

/// Shared waiting helpers for the socket and native host fixtures.
///
/// Why these tests are synchronous. The hosted runner has three cores, so the cooperative pool has three threads, and the
/// exhaustive voice key walks are CPU bound for minutes each. While they hold every pool thread, an async test that
/// suspends cannot resume (seen as 2268 s on CI and 632 s locally), and the wall clock deadlines and socket timeouts
/// it started keep running. A synchronous test keeps its thread from start to end, so its clock only runs while it runs.
/// Waits also look at their condition once more after the deadline, and blocking calls run on dispatch threads.
enum PollingWait {
    /// Generous bound for something that normally takes milliseconds. A pass returns at once, so it costs nothing.
    static let eventBound: Duration = .seconds(20)

    /// True once `condition` holds. Gives up at `timeout` or when `giveUp` says so, and then checks one last time.
    static func until(timeout: Duration = eventBound,
                      giveUp: () -> Bool = { false },
                      pause: () -> Void = { usleep(5_000) },
                      _ condition: () -> Bool) -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if condition() { return true }
            pause()
        } while !giveUp() && ContinuousClock.now < deadline
        return condition()
    }

    /// Runs a blocking call on a dispatch thread, so a synchronous test can keep several in flight.
    static func start<T: Sendable>(_ work: @escaping @Sendable () -> T) -> Pending<T> {
        let pending = Pending<T>()
        DispatchQueue.global(qos: .userInitiated).async { pending.finish(work()) }
        return pending
    }

    final class Pending<T: Sendable>: @unchecked Sendable {
        private let done = DispatchSemaphore(value: 0)
        private var result: T?

        fileprivate func finish(_ value: T) {
            result = value
            done.signal()
        }

        /// Blocks until the work ends. Call it once.
        func wait() -> T {
            done.wait()
            return result!
        }
    }
}
