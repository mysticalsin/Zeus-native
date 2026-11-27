import Testing
@testable import ZeusCore

struct StepLimitDrawTests {
    @Test func aStepLimitShowsTheCount() throws {
        let plan = try #require(StepLimitDraw.from(line: "I stopped after 8 steps without finishing. Tell me how to go on."))
        func cards(_ plan: StepLimitDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Steps", "8"])
        #expect(plan.boltCaption(at: 0) == "Steps")
        #expect(plan.boltCaption(at: 100) == "8")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankCountAndOtherStopsAreNotTheLimit() {
        #expect(StepLimitDraw.from(line: "") == nil)
        #expect(StepLimitDraw.from(line: "I stopped after steps without finishing. Tell me how to go on.") == nil)
        #expect(StepLimitDraw.from(line: "Stopped.") == nil)
        #expect(StepLimitDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
        #expect(StepLimitDraw.from(line: "Okay, I won't send it.") == nil)
    }
}
