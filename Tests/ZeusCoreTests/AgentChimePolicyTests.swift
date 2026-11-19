import Foundation
import Testing
@testable import ZeusCore

@Suite struct AgentChimePolicyTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aStartedAgentIsSilentUnlessTheStartSettingIsOn() {
        var off = AgentChimePolicy()
        #expect(off.session("a", status: .working, at: at(0), startEnabled: false) == nil)
        var on = AgentChimePolicy()
        #expect(on.session("a", status: .working, at: at(0), startEnabled: true) == .start)
    }

    @Test func aShortAutomatedTurnNeverChimesDone() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(policy.session("a", status: .done, at: at(19), startEnabled: false) == nil)
    }

    @Test func aTurnOfTwentySecondsChimesDoneOnce() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(policy.session("a", status: .done, at: at(20), startEnabled: false) == .done)
        #expect(policy.session("a", status: .done, at: at(40), startEnabled: false) == nil)
    }

    @Test func eachSessionTimesItsOwnStretch() {
        var policy = AgentChimePolicy()
        _ = policy.session("long", status: .working, at: at(0), startEnabled: false)
        _ = policy.session("short", status: .working, at: at(25), startEnabled: false)
        #expect(policy.session("short", status: .done, at: at(30), startEnabled: false) == nil)
        #expect(policy.session("long", status: .done, at: at(31), startEnabled: false) == .done)
    }

    @Test func waitingOnAnApprovalDoesNotRestartTheStretch() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        _ = policy.session("a", status: .needsYou, at: at(10), startEnabled: false)
        _ = policy.session("a", status: .working, at: at(15), startEnabled: false)
        #expect(policy.session("a", status: .done, at: at(21), startEnabled: false) == .done)
    }

    @Test func aFailedTurnIsNotADoneChime() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(policy.session("a", status: .failed, at: at(60), startEnabled: false) == nil)
    }

    @Test func atMostOneChimeEveryThreeSecondsAcrossSessions() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        _ = policy.session("b", status: .working, at: at(0), startEnabled: false)
        #expect(policy.session("a", status: .done, at: at(30), startEnabled: false) == .done)
        #expect(policy.session("b", status: .done, at: at(32.9), startEnabled: false) == nil)
        _ = policy.session("b", status: .working, at: at(33), startEnabled: false)
        #expect(policy.session("b", status: .done, at: at(60), startEnabled: false) == .done)
    }

    @Test func aNewApprovalChimesAndAFastAnswerStaysSilent() {
        var policy = AgentChimePolicy()
        #expect(policy.approval(visible: true, at: at(0)) == .approval)
        #expect(policy.approval(visible: true, at: at(1)) == nil)
        #expect(policy.approval(visible: false, at: at(1.9)) == nil)
    }

    @Test func aSlowAnswerChimesOnceTheApprovalWasVisibleTwoSeconds() {
        var policy = AgentChimePolicy()
        _ = policy.approval(visible: true, at: at(0))
        #expect(policy.approval(visible: false, at: at(5)) == .answer)
        #expect(policy.approval(visible: false, at: at(6)) == nil)
    }

    @Test func aCoalescedApprovalStillTimesItsAnswer() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        #expect(policy.session("a", status: .done, at: at(30), startEnabled: false) == .done)
        #expect(policy.approval(visible: true, at: at(31)) == nil)
        #expect(policy.approval(visible: false, at: at(40)) == .answer)
    }

    @Test func forgettingASessionDropsItsStretch() {
        var policy = AgentChimePolicy()
        _ = policy.session("a", status: .working, at: at(0), startEnabled: false)
        policy.forget(keeping: [])
        #expect(policy.session("a", status: .done, at: at(60), startEnabled: false) == nil)
    }
}
