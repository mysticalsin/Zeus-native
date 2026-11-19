import Foundation

/// Shared waiting helpers for the socket and native host fixtures.
enum PollingWait {
    /// True once `condition` holds. Gives up at `timeout` or when `giveUp` says so.
    static func until(timeout: Duration,
                      giveUp: () -> Bool = { false },
                      pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(5)) },
                      _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if condition() { return true }
            try await pause()
        } while !giveUp() && ContinuousClock.now < deadline
        return false
    }
}
