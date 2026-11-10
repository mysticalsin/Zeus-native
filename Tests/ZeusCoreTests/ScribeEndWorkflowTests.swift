import Foundation
import Testing
@testable import ZeusCore

@Suite("Scribe owned call end confirmation")
struct ScribeEndWorkflowTests {
    private let owner = ScribeCallProcessIdentity(pid: 42, bundleID: "synthetic.call", launchedAt: 100)

    @Test func explicitStopWaitsNineSecondsAndEmitsOnlyOneStopRequest() {
        let id = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: id, boundCall: nil)
        let applied1 = flow.endNow(session: id)
        #expect(!applied1)
        let applied2 = flow.requestEnd(session: id, now: 20)
        #expect(applied2)
        #expect(flow.reason == .requestedByUser)
        #expect(flow.remaining(now: 20) == 9)
        let applied3 = flow.requestEnd(session: id, now: 25)
        #expect(!applied3)
        #expect(flow.remaining(now: 25) == 4)
        let applied4 = flow.stopIfDue(session: id, now: 28.999)
        #expect(!applied4)
        let applied5 = flow.stopIfDue(session: id, now: 29)
        #expect(applied5)
        let applied6 = flow.stopIfDue(session: id, now: 30)
        #expect(!applied6)
        let applied7 = flow.endNow(session: id)
        #expect(!applied7)
        let applied8 = flow.keepRecording(session: id)
        #expect(!applied8)
        #expect(flow.remaining(now: 30) == nil)
    }

    @Test func onlyTheExactBoundProcessInstanceCanStartAutomaticConfirmation() {
        let id = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: id, boundCall: owner)
        for other in [ScribeCallProcessIdentity(pid: 99, bundleID: owner.bundleID, launchedAt: owner.launchedAt),
                      ScribeCallProcessIdentity(pid: owner.pid, bundleID: "different.app", launchedAt: owner.launchedAt),
                      ScribeCallProcessIdentity(pid: owner.pid, bundleID: owner.bundleID, launchedAt: 101)] {
            let applied9 = flow.applicationTerminated(other, session: id, now: 20)
            #expect(!applied9)
            #expect(flow.deadline == nil)
        }
        let applied10 = flow.applicationTerminated(owner, session: id, now: 20)
        #expect(applied10)
        #expect(flow.reason == .boundCallAppClosed)
        let applied11 = flow.applicationTerminated(owner, session: id, now: 22)
        #expect(!applied11)
        #expect(flow.remaining(now: 22) == 7)
    }

    @Test func keepingAtTheDeadlineSuppressesDuplicateAppExitButExplicitStopCanRearm() {
        let id = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: id, boundCall: owner)
        let applied12 = flow.applicationTerminated(owner, session: id, now: 20)
        #expect(applied12)
        #expect(flow.remaining(now: 29) == 0)
        let applied13 = flow.keepRecording(session: id)
        #expect(applied13)
        let applied14 = flow.stopIfDue(session: id, now: 29)
        #expect(!applied14)
        let applied15 = flow.applicationTerminated(owner, session: id, now: 30)
        #expect(!applied15)
        let applied16 = flow.requestEnd(session: id, now: 31)
        #expect(applied16)
        #expect(flow.reason == .requestedByUser)
        let applied17 = flow.endNow(session: id)
        #expect(applied17)
        let applied18 = flow.endNow(session: id)
        #expect(!applied18)
    }

    @Test func exitDuringManualConfirmationIsConsumedWhenTheUserKeepsRecording() {
        let id = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: id, boundCall: owner)
        let applied19 = flow.requestEnd(session: id, now: 20)
        #expect(applied19)
        let applied20 = flow.applicationTerminated(owner, session: id, now: 21)
        #expect(!applied20)
        #expect(flow.reason == .requestedByUser)
        let applied21 = flow.keepRecording(session: id)
        #expect(applied21)
        let applied22 = flow.applicationTerminated(owner, session: id, now: 22)
        #expect(!applied22)
    }

    @Test func replacingTheSessionRejectsEveryOldCommandAndNotification() {
        let old = ScribeSessionID(), current = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: old, boundCall: owner)
        let applied23 = flow.requestEnd(session: old, now: 10)
        #expect(applied23)
        flow.begin(session: current, boundCall: nil)
        let applied24 = flow.requestEnd(session: old, now: 20)
        #expect(!applied24)
        let applied25 = flow.applicationTerminated(owner, session: old, now: 20)
        #expect(!applied25)
        let applied26 = flow.stopIfDue(session: old, now: 30)
        #expect(!applied26)
        let applied27 = flow.keepRecording(session: old)
        #expect(!applied27)
        let applied28 = flow.endNow(session: old)
        #expect(!applied28)
        let applied29 = flow.applicationTerminated(owner, session: current, now: 20)
        #expect(!applied29)
        #expect(flow.deadline == nil)
        #expect(!flow.stopRequested)
    }

    @Test func nonfiniteNegativeAndUnrepresentableClocksCannotArmOrComplete() {
        let id = ScribeSessionID()
        var flow = ScribeEndWorkflow()
        flow.begin(session: id, boundCall: owner)
        for now: TimeInterval in [.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            let applied30 = flow.requestEnd(session: id, now: now)
            #expect(!applied30)
            let applied31 = flow.applicationTerminated(owner, session: id, now: now)
            #expect(!applied31)
            #expect(flow.deadline == nil)
        }
        let applied32 = flow.applicationTerminated(owner, session: id, now: 10)
        #expect(applied32)
        for now: TimeInterval in [.nan, .infinity, -.infinity, -1] {
            let applied33 = flow.stopIfDue(session: id, now: now)
            #expect(!applied33)
            #expect(flow.remaining(now: now) == nil)
        }
        let applied34 = flow.stopIfDue(session: id, now: 19)
        #expect(applied34)
    }

    @Test func invalidProcessIdentityNeverBindsButManualStopStillWorks() {
        for identity in [ScribeCallProcessIdentity(pid: 0, bundleID: "call", launchedAt: 1),
                         ScribeCallProcessIdentity(pid: 4, bundleID: " ", launchedAt: 1),
                         ScribeCallProcessIdentity(pid: 4, bundleID: "call", launchedAt: .nan)] {
            let id = ScribeSessionID()
            var flow = ScribeEndWorkflow()
            flow.begin(session: id, boundCall: identity)
            #expect(flow.boundCall == nil)
            let applied35 = flow.applicationTerminated(identity, session: id, now: 10)
            #expect(!applied35)
            let applied36 = flow.requestEnd(session: id, now: 10)
            #expect(applied36)
        }
    }
}
