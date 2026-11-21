import Testing
import ZeusCore

@Suite("Approval card wait")
struct ApprovalWaitTests {
    private typealias Wait = ApprovalWait

    @Test func beginArmsOneTimeout() {
        let (phase, effects) = Wait.reduce(.idle, .begin(id: "card"))
        #expect(phase == .waiting(id: "card"))
        #expect(effects == [.armTimeout(id: "card")])
    }

    @Test func answeringAnApprovalCancelsItsTimeout() {
        let (waiting, _) = Wait.reduce(.idle, .begin(id: "card"))
        let (phase, effects) = Wait.reduce(waiting, .answer(id: "card"))
        #expect(phase == .idle)
        #expect(effects == [.resolve(id: "card")])
        let (late, lateEffects) = Wait.reduce(phase, .timeout(id: "card"))
        #expect(late == .idle)
        #expect(lateEffects.isEmpty)
    }

    @Test func timingOutResolvesOnce() {
        let (waiting, _) = Wait.reduce(.idle, .begin(id: "card"))
        let (phase, effects) = Wait.reduce(waiting, .timeout(id: "card"))
        #expect(phase == .idle)
        #expect(effects == [.resolve(id: "card")])
        let (_, again) = Wait.reduce(phase, .answer(id: "card"))
        #expect(again.isEmpty)
    }

    @Test func aStaleOrOverlappingEventDoesNothing() {
        let (waiting, _) = Wait.reduce(.idle, .begin(id: "card"))
        #expect(Wait.reduce(waiting, .answer(id: "other")).1.isEmpty)
        #expect(Wait.reduce(waiting, .timeout(id: "other")).0 == waiting)
        #expect(Wait.reduce(waiting, .begin(id: "next")).1.isEmpty)
        #expect(Wait.reduce(.idle, .timeout(id: "card")).1.isEmpty)
    }
}
