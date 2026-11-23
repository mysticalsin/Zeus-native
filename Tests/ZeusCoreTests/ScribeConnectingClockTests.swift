import Foundation
import Testing
@testable import ZeusCore

/// The session machine's connecting deadline, with an injected instant and no sleep.
/// The presentation stays on connecting until that tick moves the phase to a failure a new start can retry.
@Suite("Scribe connecting clock")
struct ScribeConnectingClockTests {
    @Test func controllerClockFiresTheConnectingDeadlineWithoutSleeping() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 10)
        let deadline = ScribeConnectingClock.begin(now: 10)
        #expect(deadline == 10 + ScribeSessionMachine.connectingLimit)
        #expect(ScribePresentation.state(for: machine.phase, elapsed: 3_600) == .connecting)

        let early = ScribeConnectingClock.tick(&machine, now: 54.999, deadline: deadline)
        #expect(early.outcome == .invalid)
        #expect(early.events.isEmpty)
        #expect(machine.phase == .starting(id))
        #expect(ScribePresentation.state(for: machine.phase, elapsed: 3_600) == .connecting)

        let fired = ScribeConnectingClock.tick(&machine, now: deadline ?? 0, deadline: deadline)
        #expect(fired.isApplied)
        #expect(fired.events == [.failed(id, reason: ScribeSessionMachine.connectingExpiredReason)])
        #expect(machine.phase == .failed(id, reason: ScribeSessionMachine.connectingExpiredReason))
        #expect(!machine.phase.isActive)
        #expect(ScribePresentation.state(for: machine.phase) == .failed(ScribeSessionMachine.connectingExpiredReason))
        #expect(ScribeConnectingClock.stops(after: machine.phase))

        let retry = ScribeSessionID()
        let again = machine.start(retry, now: (deadline ?? 0) + 1)
        #expect(again.isApplied)
        #expect(machine.phase == .starting(retry))
        #expect(ScribePresentation.state(for: machine.phase) == .connecting)

        var idle = ScribeSessionMachine()
        #expect(ScribeConnectingClock.tick(&idle, now: 90, deadline: deadline).outcome == .invalid)
        #expect(idle.phase == .idle)

        var live = ScribeSessionMachine()
        let liveID = ScribeSessionID()
        _ = live.start(liveID, now: 0)
        _ = live.acknowledgeCapture(liveID, now: 1)
        #expect(ScribeConnectingClock.stops(after: live.phase))
        let connected = ScribeConnectingClock.tick(&live, now: 90, deadline: ScribeConnectingClock.begin(now: 0))
        #expect(connected.outcome == .invalid)
        #expect(live.phase == .recording(liveID, since: 1))
    }
}
