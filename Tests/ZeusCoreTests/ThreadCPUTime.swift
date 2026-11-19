import Foundation

/// Cost tests read this thread's CPU clock, not the wall clock. A busy machine that preempts the test then
/// does not count as work the code under test would do. The limits stay as they were.
enum ThreadCPUTime {
    /// Seconds of CPU this thread has used so far.
    static func now() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }

    /// Seconds of CPU this thread spends running `work`.
    static func measure(_ work: () -> Void) -> Double {
        let start = now()
        work()
        return now() - start
    }
}
