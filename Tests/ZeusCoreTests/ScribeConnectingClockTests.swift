import Foundation
import Testing
@testable import ZeusCore

/// The controller's connecting clock, with an injected instant and no sleep.
/// Fails until `ScribeConnectingClock.tick` hands that instant to the session machine.
@Suite("Scribe connecting clock")
struct ScribeConnectingClockTests {
    @Test func controllerClockFiresTheConnectingDeadlineWithoutSleeping() {
        let id = ScribeSessionID()
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 10)
        let deadline = ScribeConnectingClock.begin(now: 10)
        #expect(deadline == 10 + ScribeSessionMachine.connectingLimit)

        let early = ScribeConnectingClock.tick(&machine, now: 54.999, deadline: deadline)
        #expect(early.outcome == .invalid)
        #expect(early.events.isEmpty)
        #expect(machine.phase == .starting(id))

        let fired = ScribeConnectingClock.tick(&machine, now: deadline ?? 0, deadline: deadline)
        #expect(fired.isApplied)
        #expect(fired.events == [.failed(id, reason: ScribeSessionMachine.connectingExpiredReason)])
        #expect(machine.phase == .failed(id, reason: ScribeSessionMachine.connectingExpiredReason))
        #expect(ScribeConnectingClock.stops(after: machine.phase))

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
