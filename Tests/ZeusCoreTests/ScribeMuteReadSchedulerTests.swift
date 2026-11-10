import Foundation
import Testing
@testable import ZeusCore

/// Real scheduler workers, blocked only by disposable semaphores. No CoreAudio or device reads.
@Suite("Bounded Scribe mute readers", .serialized)
struct ScribeMuteReadSchedulerTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }

    private func eventually(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }

    @Test func twoBlockedReadersRejectEveryFurtherWatchdogRefreshWithoutQueueing() async throws {
        let scheduler = ScribeMuteReadScheduler()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal(); release.signal() }
        let began = Counter()
        let blocked: @Sendable () -> Void = { began.increment(); _ = release.wait(timeout: .now() + 5) }
        #expect(scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked))
        try await eventually { began.value == 1 }
        #expect(!scheduler.schedule(now: 12.99, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked))
        #expect(scheduler.schedule(now: 13, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked))
        try await eventually { began.value == 2 }
        for now in stride(from: 16.0, through: 30_016, by: 3) {
            #expect(!scheduler.schedule(now: now, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked))
        }
        #expect(scheduler.activeReadCount == 2)
        #expect(began.value == 2)
        release.signal(); release.signal()
        try await eventually { scheduler.activeReadCount == 0 }
        #expect(began.value == 2, "Rejected refreshes must not become queued work after a slot returns")
    }

    @Test func oneStalledReaderDoesNotQueueItsReplacementAndReturnedSlotCanRecover() async throws {
        let scheduler = ScribeMuteReadScheduler()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let began = Counter()
        #expect(scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: 0.5, watchdog: 3) {
            began.increment(); _ = release.wait(timeout: .now() + 5)
        })
        try await eventually { began.value == 1 }
        #expect(scheduler.schedule(now: 13, evidenceTakenAt: nil, interval: 0.5, watchdog: 3) { began.increment() })
        try await eventually { began.value == 2 && scheduler.activeReadCount == 1 }
        #expect(!scheduler.schedule(now: 13.49, evidenceTakenAt: 13, interval: 0.5, watchdog: 3) { began.increment() })
        #expect(scheduler.schedule(now: 13.5, evidenceTakenAt: 13, interval: 0.5, watchdog: 3) { began.increment() })
        try await eventually { began.value == 3 && scheduler.activeReadCount == 1 }
        release.signal()
        try await eventually { scheduler.activeReadCount == 0 }
    }

    @Test func simultaneousRefreshRequestsShareTheTwoReaderBudget() async throws {
        let scheduler = ScribeMuteReadScheduler()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal(); release.signal() }
        let blocked: @Sendable () -> Void = { _ = release.wait(timeout: .now() + 5) }
        #expect(scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked))
        let admitted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    scheduler.schedule(now: 13, evidenceTakenAt: nil, interval: 0.5, watchdog: 3, read: blocked)
                }
            }
            var total = 0
            for await allowed in group where allowed { total += 1 }
            return total
        }
        #expect(admitted == 1)
        #expect(scheduler.activeReadCount == 2)
        release.signal(); release.signal()
        try await eventually { scheduler.activeReadCount == 0 }
    }

    @Test func blockedReadersCannotKeepStaleEvidenceFreshOrLetLateUnmutedReplaceNewerMute() async throws {
        let scheduler = ScribeMuteReadScheduler()
        let ingress = ScribeMicrophoneIngress()
        let session = ScribeSessionID()
        ingress.begin(session: session)
        ingress.record(state: .unmuted, readStart: 10, readEnd: 10.1, externalInputDetected: false)
        #expect(ingress.acknowledge(session: session, at: 10.1))
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        #expect(scheduler.schedule(now: 10.5, evidenceTakenAt: 10, interval: 0.5, watchdog: 3) {
            _ = release.wait(timeout: .now() + 5)
            ingress.record(state: .unmuted, readStart: 10.5, readEnd: 13.7, externalInputDetected: false)
        })
        #expect(ingress.currentState(now: 12) == .unknown)
        #expect(!ingress.admit(session: session, start: 11.8, duration: 0.1, now: 12) {
            Issue.record("An expired reading touched microphone sample memory"); return true
        })
        #expect(scheduler.schedule(now: 13.5, evidenceTakenAt: 10, interval: 0.5, watchdog: 3) {
            ingress.record(state: .muted, readStart: 13.5, readEnd: 13.6, externalInputDetected: false)
        })
        try await eventually { scheduler.activeReadCount == 1 && ingress.currentState(now: 13.7) == .muted }
        release.signal()
        try await eventually { scheduler.activeReadCount == 0 }
        #expect(ingress.currentState(now: 13.8) == .muted)
        #expect(!ingress.admit(session: session, start: 13.7, duration: 0.05, now: 13.8) {
            Issue.record("A late unmuted result replaced newer mute evidence"); return true
        })
    }

    @Test func invalidOrBackwardsTimingDoesNotLaunchReplacementReaders() async throws {
        let scheduler = ScribeMuteReadScheduler()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let began = Counter()
        for now in [Double.nan, .infinity, -.infinity] {
            #expect(!scheduler.schedule(now: now, evidenceTakenAt: nil, interval: 0.5, watchdog: 3) { began.increment() })
        }
        for invalid in [Double.nan, .infinity, 0, -1] {
            #expect(!scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: invalid, watchdog: 3) { began.increment() })
            #expect(!scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: 0.5, watchdog: invalid) { began.increment() })
        }
        #expect(!scheduler.schedule(now: 10, evidenceTakenAt: .nan, interval: 0.5, watchdog: 3) { began.increment() })
        #expect(scheduler.schedule(now: 10, evidenceTakenAt: nil, interval: 0.5, watchdog: 3) {
            began.increment(); _ = release.wait(timeout: .now() + 5)
        })
        #expect(!scheduler.schedule(now: 9, evidenceTakenAt: nil, interval: 0.5, watchdog: 3) { began.increment() })
        release.signal()
        try await eventually { scheduler.activeReadCount == 0 }
        #expect(began.value == 1)
    }
}
