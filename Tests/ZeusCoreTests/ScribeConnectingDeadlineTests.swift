import Foundation
import Testing
@testable import ZeusCore

/// The connecting phase (`.starting`) has to end on a clock the session machine owns.
/// The presentation keeps mapping `.starting` to `.connecting` for any elapsed value, so a view
/// timer cannot be what leaves "Connecting".
@Suite("Scribe connecting deadline")
struct ScribeConnectingDeadlineTests {
    private let limit: TimeInterval = 45
    private let reason = "Connecting took too long. Try again."

    @Test func aClockAtTheDeadlineFailsConnectingAndANewStartCanRetry() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        let began = machine.start(id, now: 10)
        #expect(began.isApplied)
        #expect(began.events.isEmpty)
        #expect(machine.phase == .starting(id))
        #expect(machine.startedAt == 10)
        #expect(ScribePresentation.state(for: machine.phase) == .connecting)

        let early = machine.tick(now: 10 + limit - 0.001)
        #expect(early.outcome == .invalid)
        #expect(early.events.isEmpty)
        #expect(machine.phase == .starting(id))

        let expired = machine.tick(now: 10 + limit)
        #expect(expired.isApplied)
        #expect(expired.events == [.failed(id, reason: reason)])
        #expect(machine.phase == .failed(id, reason: reason))
        #expect(!machine.phase.isActive)

        let shown = ScribePresentation.state(for: machine.phase)
        #expect(shown == .failed(reason))
        #expect(shown.announcement == "Scribe stopped. \(reason)")

        // The deadline does not start another session. A later clock stays on the failure.
        let later = machine.tick(now: 10 + limit + 30)
        #expect(later.outcome == .invalid)
        #expect(later.events.isEmpty)
        #expect(machine.phase == .failed(id, reason: reason))

        // The same session id is not a retry. A new start is the person's tap.
        #expect(machine.start(id, now: 80).outcome == .invalid)
        #expect(machine.phase == .failed(id, reason: reason))
        let next = ScribeSessionID()
        let retry = machine.start(next, now: 80)
        #expect(retry.isApplied)
        #expect(retry.events.isEmpty)
        #expect(machine.phase == .starting(next))
        #expect(ScribePresentation.state(for: machine.phase) == .connecting)
    }

    @Test func presentationStaysConnectingForAnyElapsedValue() {
        let id = ScribeSessionID()
        for elapsed in [0, 8, 20, 45, 90, 3_600] as [TimeInterval] {
            let shown = ScribePresentation.state(for: .starting(id), elapsed: elapsed, revealElapsed: elapsed)
            #expect(shown == .connecting)
            #expect(shown.announcement == "Connecting")
        }
    }

    @Test func acknowledgementBeforeTheDeadlineStillStartsRecording() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        #expect(machine.tick(now: limit - 1).outcome == .invalid)
        #expect(machine.acknowledgeCapture(id, now: limit - 1).events == [.recordingStarted(id)])
        #expect(machine.tick(now: limit + 30).outcome == .invalid)
        #expect(machine.phase == .recording(id, since: limit - 1))
        #expect(ScribePresentation.state(for: machine.phase, elapsed: 3) == .recording(elapsed: 3))
    }

    @Test func aLateAcknowledgementAfterTheDeadlineDoesNotStartRecording() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        _ = machine.tick(now: limit)
        #expect(machine.acknowledgeCapture(id, now: limit + 1).outcome == .invalid)
        #expect(machine.phase == .failed(id, reason: reason))
        #expect(ScribePresentation.state(for: machine.phase) == .failed(reason))
    }

    @Test func aReplacedConnectingSessionGetsItsOwnDeadline() {
        let old = ScribeSessionID()
        let new = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(old, now: 0)
        let replaced = machine.start(new, now: 40)
        #expect(replaced.events == [.cancelled(old)])
        #expect(machine.tick(now: 45).outcome == .invalid)
        #expect(machine.phase == .starting(new))
        let expired = machine.tick(now: 40 + limit)
        #expect(expired.events == [.failed(new, reason: reason)])
        #expect(machine.phase == .failed(new, reason: reason))
    }

    @Test func aNonFiniteClockDoesNotLeaveConnecting() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        #expect(machine.tick(now: .nan).outcome == .invalid)
        #expect(machine.tick(now: .infinity).outcome == .invalid)
        #expect(machine.phase == .starting(id))
    }

    @Test func cancelDuringConnectingDoesNotBecomeTheDeadlineFailure() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        #expect(machine.cancel(id).events == [.cancelled(id)])
        #expect(machine.tick(now: limit).outcome == .invalid)
        #expect(machine.phase == .idle)
    }

    @Test func endingCountdownTickStillDoesNotEndCapture() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 0)
        _ = machine.acknowledgeCapture(id, now: 1)
        let request = machine.requestEnd(id, now: 10, grace: 5)
        #expect(request.events == [.endingCountdown(id, remaining: 5)])
        let tick = machine.tick(now: 100)
        #expect(tick.events == [.endingCountdown(id, remaining: 0)])
        #expect(machine.phase == .ending(id, deadline: 15))
        #expect(!tick.events.contains(.recordingEnded(id)))
        #expect(!tick.events.contains(.failed(id, reason: reason)))
    }
}
