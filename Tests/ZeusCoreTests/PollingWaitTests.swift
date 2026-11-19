import Foundation
import Testing

@Suite("Polling wait")
struct PollingWaitTests {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var set = false
        var value: Bool { lock.withLock { set } }
        func raise() { lock.withLock { set = true } }
    }

    @Test func aLateWakeUpStillSeesAConditionThatBecameTrueDuringTheStall() async throws {
        // A starved executor resumes the waiter long after its deadline. The condition was met meanwhile.
        let flag = Flag()
        let met = try await PollingWait.until(timeout: .milliseconds(50), pause: {
            usleep(200_000)
            flag.raise()
        }) { flag.value }
        #expect(met, "the condition held at the late wake-up, so the wait must report it")
    }

    @Test func aConditionThatNeverHoldsStopsAtTheDeadline() async throws {
        let started = ContinuousClock.now
        let met = try await PollingWait.until(timeout: .milliseconds(100)) { false }
        #expect(!met)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func giveUpEndsTheWaitBeforeTheDeadline() async throws {
        let started = ContinuousClock.now
        let met = try await PollingWait.until(timeout: .seconds(30), giveUp: { true }) { false }
        #expect(!met)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
