import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// The page clock has to drive the session machine while Scribe is connecting.
/// A direct machine tick is not enough: `start` is the person's tap, and `tickClock`
/// is the tick the connecting timer calls. These fail until that wiring exists.
@MainActor @Suite("Scribe connecting deadline")
struct ScribeConnectingDeadlineTests {
    private let limit: TimeInterval = 45
    private let reason = "Connecting took too long. Try again."

    private final class Clock {
        var time: TimeInterval = 0
    }

    private final class Capture: ScribeCaptureProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable (ScribeCaptureEvent) -> Void)?
        func start(session: ScribeSessionID, frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
                   events: @escaping @Sendable (ScribeCaptureEvent) -> Void) {
            lock.withLock { callback = events }
        }
        func stop(session: ScribeSessionID) {}
        func send(_ event: ScribeCaptureEvent) { lock.withLock { callback }?(event) }
    }

    private final class Session {
        let clock = Clock()
        let capture = Capture()
        let controller: ScribeController
        let suite: String

        init() throws {
            suite = NSTemporaryDirectory() + "scribe-connecting-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let manualClock = clock
            controller = ScribeController(
                provider: capture,
                monotonicClock: { manualClock.time },
                cancellationDefaults: defaults,
                optInDefaults: defaults
            )
        }

        func close() {
            switch controller.phase {
            case .idle: break
            case .failed, .complete: controller.closeNotes()
            default: controller.cancel()
            }
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }

        /// The person's tap. This is the only way these tests start Scribe.
        @discardableResult
        func tap(at now: TimeInterval) throws -> ScribeSessionID {
            clock.time = now
            controller.start()
            return try #require(controller.phase.sessionID)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for a capture event")
    }

    @Test func aClockAtTheDeadlineFailsConnectingAndANewStartCanRetry() async throws {
        let session = try Session()
        defer { session.close() }
        let id = try session.tap(at: 10)
        #expect(session.controller.phase == .starting(id))
        #expect(session.controller.isSessionClockRunning)

        session.clock.time = 10 + limit - 0.001
        session.controller.tickClock()
        #expect(session.controller.phase == .starting(id))

        session.clock.time = 10 + limit
        session.controller.tickClock()
        #expect(session.controller.phase == .failed(id, reason: reason))
        #expect(!session.controller.phase.isActive)
        #expect(!session.controller.isSessionClockRunning)
        #expect(session.controller.presentation(at: Date(), reduceMotion: false) == .failed(reason))

        // The deadline does not tap again. Retry is the person's button.
        session.controller.tickClock()
        #expect(session.controller.phase == .failed(id, reason: reason))
        session.controller.retry()
        let next = try #require(session.controller.phase.sessionID)
        #expect(next != id)
        #expect(session.controller.phase == .starting(next))
        #expect(session.controller.isSessionClockRunning)
        session.clock.time = 10 + limit + 1
        session.controller.tickClock()
        #expect(session.controller.phase == .starting(next))
    }

    @Test func presentationStaysConnectingUntilTheControllerClockFails() async throws {
        let id = ScribeSessionID()
        for elapsed in [0, 8, 20, 45, 90, 3_600] as [TimeInterval] {
            let shown = ScribePresentation.state(for: .starting(id), elapsed: elapsed, revealElapsed: elapsed)
            #expect(shown == .connecting)
            #expect(shown.announcement == "Connecting")
        }

        let session = try Session()
        defer { session.close() }
        let started = try session.tap(at: 0)
        #expect(session.controller.isSessionClockRunning)
        #expect(session.controller.presentation(at: Date(), reduceMotion: true) == .connecting)
        session.clock.time = limit
        session.controller.tickClock()
        let failed = session.controller.presentation(at: Date(), reduceMotion: true)
        #expect(failed == .failed(reason))
        #expect(failed.announcement == "Scribe stopped. \(reason)")
        #expect(session.controller.phase == .failed(started, reason: reason))
    }

    @Test func acknowledgementBeforeTheDeadlineStillStartsRecording() async throws {
        let session = try Session()
        defer { session.close() }
        let id = try session.tap(at: 0)
        #expect(session.controller.isSessionClockRunning)
        session.clock.time = limit - 1
        session.controller.tickClock()
        #expect(session.controller.phase == .starting(id))

        session.capture.send(.captureAcknowledged(id))
        try await waitUntil { session.controller.phase == .recording(id, since: limit - 1) }
        session.clock.time = limit + 30
        session.controller.tickClock()
        #expect(session.controller.phase == .recording(id, since: limit - 1))
        #expect(session.controller.presentation(at: Date(), reduceMotion: false) == .recording(elapsed: 31))
    }

    @Test func aLateAcknowledgementAfterTheDeadlineDoesNotStartRecording() async throws {
        let session = try Session()
        defer { session.close() }
        let id = try session.tap(at: 0)
        #expect(session.controller.isSessionClockRunning)
        session.clock.time = limit
        session.controller.tickClock()
        #expect(session.controller.phase == .failed(id, reason: reason))

        session.capture.send(.captureAcknowledged(id))
        try await Task.sleep(for: .milliseconds(80))
        #expect(session.controller.phase == .failed(id, reason: reason))
        #expect(session.controller.presentation(at: Date(), reduceMotion: false) == .failed(reason))
    }

    @Test func aNewTapAfterCancelGetsItsOwnDeadline() async throws {
        let session = try Session()
        defer { session.close() }
        let first = try session.tap(at: 0)
        #expect(session.controller.isSessionClockRunning)
        session.controller.start()
        #expect(session.controller.phase == .starting(first))

        session.clock.time = 10
        session.controller.cancel()
        #expect(session.controller.phase == .idle)
        let second = try session.tap(at: 40)
        #expect(second != first)
        #expect(session.controller.isSessionClockRunning)
        session.clock.time = 45
        session.controller.tickClock()
        #expect(session.controller.phase == .starting(second))
        session.clock.time = 40 + limit
        session.controller.tickClock()
        #expect(session.controller.phase == .failed(second, reason: reason))
    }

    @Test func aNonFiniteClockDoesNotLeaveConnecting() async throws {
        let held = try Session()
        defer { held.close() }
        let id = try held.tap(at: 0)
        #expect(held.controller.isSessionClockRunning)
        held.clock.time = .nan
        held.controller.tickClock()
        held.clock.time = .infinity
        held.controller.tickClock()
        #expect(held.controller.phase == .starting(id))

        let finite = try Session()
        defer { finite.close() }
        let other = try finite.tap(at: 3)
        finite.clock.time = 3 + limit
        finite.controller.tickClock()
        #expect(finite.controller.phase == .failed(other, reason: reason))
    }

    @Test func cancelDuringConnectingDoesNotBecomeTheDeadlineFailure() async throws {
        let session = try Session()
        defer { session.close() }
        let id = try session.tap(at: 0)
        #expect(session.controller.isSessionClockRunning)
        session.controller.cancel()
        #expect(session.controller.phase == .idle)
        #expect(!session.controller.isSessionClockRunning)
        session.clock.time = limit
        session.controller.tickClock()
        #expect(session.controller.phase == .idle)

        let open = try Session()
        defer { open.close() }
        let still = try open.tap(at: 1)
        open.clock.time = 1 + limit
        open.controller.tickClock()
        #expect(open.controller.phase == .failed(still, reason: reason))
        #expect(id != still)
    }

    @Test func endingCountdownTickStillDoesNotEndCapture() async throws {
        let connecting = try Session()
        defer { connecting.close() }
        let connectingID = try connecting.tap(at: 0)
        #expect(connecting.controller.isSessionClockRunning)
        connecting.clock.time = limit
        connecting.controller.tickClock()
        #expect(connecting.controller.phase == .failed(connectingID, reason: reason))

        let session = try Session()
        defer { session.close() }
        let id = try session.tap(at: 0)
        session.capture.send(.captureAcknowledged(id))
        try await waitUntil { session.controller.isRecording }
        session.controller.requestEnd()
        session.clock.time = limit + 100
        session.controller.tickClock()
        guard case .ending(let ending, _) = session.controller.phase else {
            Issue.record("expected the end countdown, got \(session.controller.phase)")
            return
        }
        #expect(ending == id)
        #expect(session.controller.failureReason != reason)
    }
}
