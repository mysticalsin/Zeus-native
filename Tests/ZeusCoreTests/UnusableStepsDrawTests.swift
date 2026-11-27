import Testing
@testable import ZeusCore

struct UnusableStepsDrawTests {
    @Test func repeatedUnusableStepsShowUnused() throws {
        let plan = try #require(UnusableStepsDraw.from(line: "the AI kept giving steps I couldn't use."))
        func cards(_ plan: UnusableStepsDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Steps", "Unused"])
        #expect(plan.boltCaption(at: 0) == "Steps")
        #expect(plan.boltCaption(at: 100) == "Unused")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func oneUnreadStepAndAStepLimitAreNotThisStop() {
        #expect(UnusableStepsDraw.from(line: "") == nil)
        #expect(UnusableStepsDraw.from(line: "I couldn't make sense of that browser step.") == nil)
        #expect(UnusableStepsDraw.from(line: "I stopped after 12 steps without finishing. Tell me how to go on.") == nil)
        #expect(UnusableStepsDraw.from(line: "There's no earlier page in this tab.") == nil)
        #expect(UnusableStepsDraw.from(line: "Okay, I left it.") == nil)
    }
}
