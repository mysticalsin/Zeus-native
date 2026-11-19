import Foundation
import Testing
@testable import ZeusCore

private let dpNow = Date(timeIntervalSince1970: 3_000_000)

private func dpSlot(_ id: String, start: TimeInterval, end: TimeInterval? = nil) -> ScribeCalendarSlot {
    ScribeCalendarSlot(id: id, title: "Meeting \(id)", start: dpNow.addingTimeInterval(start),
                       end: end.map { dpNow.addingTimeInterval($0) }, hasCallLink: true, callApp: .teams)
}

private func dpPlan(_ mode: ScribeAutoStartMode = .ask, idle: Bool = true, mic: Bool = false,
                    slots: [ScribeCalendarSlot] = []) -> ScribeDetectorPlan {
    ScribeDetectorPlan.plan(mode: mode, machineIdle: idle, micActive: mic, slots: slots, now: dpNow)
}

@Suite("Scribe detector plan")
struct ScribeDetectorPlanTests {
    // MARK: Plan

    @Test func offWithAnIdleMachineIsStoppedWhateverElseHappens() {
        let near = [dpSlot("s1", start: 30)]
        #expect(dpPlan(.off) == .stopped)
        #expect(dpPlan(.off, mic: true, slots: near) == .stopped)
    }

    @Test func offWhileTheMachineIsBusyKeepsPollingUntilItIsIdle() {
        #expect(dpPlan(.off, idle: false) == .polling)
        #expect(dpPlan(.off, idle: false, mic: true, slots: [dpSlot("s1", start: 30)]) == .polling)
        #expect(dpPlan(.off, idle: true) == .stopped)
    }

    @Test func askMeAndAutomaticWithNothingNearListenForTheNextMeeting() {
        let slots = [dpSlot("s1", start: 3_600)]
        let wake = dpNow.addingTimeInterval(3_600 - ScribeMeetingStartPolicy.leadWindow)
        #expect(dpPlan(.ask, slots: slots) == .listening(wakeAt: wake))
        #expect(dpPlan(.automatic, slots: slots) == .listening(wakeAt: wake))
    }

    @Test func theWakeIsTwoMinutesBeforeTheEarliestMeetingThatHasNotStarted() {
        let slots = [dpSlot("late", start: 7_200), dpSlot("soon", start: 1_800), dpSlot("mid", start: 3_600)]
        #expect(dpPlan(.ask, slots: slots)
            == .listening(wakeAt: dpNow.addingTimeInterval(1_800 - ScribeMeetingStartPolicy.leadWindow)))
    }

    @Test func aMeetingThatEndedOrAlreadyStartedLongAgoSetsNoWake() {
        let slots = [dpSlot("ended", start: -3_600, end: -1_800), dpSlot("old", start: -1_000)]
        #expect(dpPlan(.ask, slots: slots) == .listening(wakeAt: dpNow.addingTimeInterval(ScribeDetectorPlan.lookAhead)))
    }

    @Test func withNoMeetingTheWakeIsTheEndOfTheLookAhead() {
        #expect(dpPlan(.ask) == .listening(wakeAt: dpNow.addingTimeInterval(ScribeDetectorPlan.lookAhead)))
    }

    @Test func aMeetingBeyondTheLookAheadDoesNotMoveTheWakePastIt() {
        let far = ScribeDetectorPlan.lookAhead + 10_000
        #expect(dpPlan(.ask, slots: [dpSlot("far", start: far)])
            == .listening(wakeAt: dpNow.addingTimeInterval(ScribeDetectorPlan.lookAhead)))
    }

    @Test func aMeetingInsideItsWindowPollsAndTheEdgesAreExact() {
        let lead = ScribeMeetingStartPolicy.leadWindow
        let late = ScribeMeetingStartPolicy.lateWindow
        #expect(dpPlan(slots: [dpSlot("s", start: lead)]) == .polling)
        #expect(dpPlan(slots: [dpSlot("s", start: lead + 1)])
            == .listening(wakeAt: dpNow.addingTimeInterval(1)))
        #expect(dpPlan(slots: [dpSlot("s", start: 0)]) == .polling)
        #expect(dpPlan(slots: [dpSlot("s", start: -late)]) == .polling)
        #expect(dpPlan(slots: [dpSlot("s", start: -late - 1)])
            == .listening(wakeAt: dpNow.addingTimeInterval(ScribeDetectorPlan.lookAhead)))
    }

    @Test func aMeetingThatEndedInsideItsWindowDoesNotPoll() {
        #expect(dpPlan(slots: [dpSlot("s", start: -100, end: 0)])
            == .listening(wakeAt: dpNow.addingTimeInterval(ScribeDetectorPlan.lookAhead)))
        #expect(dpPlan(slots: [dpSlot("s", start: -100, end: 1)]) == .polling)
    }

    @Test func aCallAppHoldingTheMicrophonePollsInEveryMode() {
        #expect(dpPlan(.ask, mic: true) == .polling)
        #expect(dpPlan(.automatic, mic: true) == .polling)
    }

    @Test func aMachineThatIsNotIdlePollsInEveryMode() {
        #expect(dpPlan(.ask, idle: false) == .polling)
        #expect(dpPlan(.automatic, idle: false) == .polling)
    }

    // MARK: Scan gate

    @Test func aWakeWhileIdleScansOnce() {
        var gate = ScribeScanGate()
        #expect(gate.state == .idle)
        #expect(gate.handle(.wake) == .scan)
        #expect(gate.state == .scanning)
        #expect(gate.handle(.finished) == nil)
        #expect(gate.state == .idle)
    }

    @Test func aWakeWhileScanningWaitsAndScansOnceMoreWhenTheFirstEnds() {
        var gate = ScribeScanGate()
        _ = gate.handle(.wake)
        #expect(gate.handle(.wake) == nil)
        #expect(gate.state == .scanningDirty)
        #expect(gate.handle(.finished) == .scan)
        #expect(gate.state == .scanning)
        #expect(gate.handle(.finished) == nil)
        #expect(gate.state == .idle)
    }

    @Test func twoWakesWhileScanningStillScanOnlyOnceMore() {
        var gate = ScribeScanGate()
        _ = gate.handle(.wake)
        #expect(gate.handle(.wake) == nil)
        #expect(gate.handle(.wake) == nil)
        #expect(gate.state == .scanningDirty)
        #expect(gate.handle(.finished) == .scan)
        #expect(gate.handle(.finished) == nil)
        #expect(gate.state == .idle)
    }

    @Test func aFinishWithNoScanRunningDoesNothing() {
        var gate = ScribeScanGate()
        #expect(gate.handle(.finished) == nil)
        #expect(gate.state == .idle)
    }
}
