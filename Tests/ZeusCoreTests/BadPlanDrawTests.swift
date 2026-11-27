import Testing
@testable import ZeusCore

struct BadPlanDrawTests {
    @Test func aPlanThatWillNotReadShowsNo() throws {
        let plan = try #require(BadPlanDraw.from(line: BadPlanDraw.line))
        func cards(_ plan: BadPlanDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Plan", "No"])
        #expect(plan.boltCaption(at: 0) == "Plan")
        #expect(plan.boltCaption(at: 100) == "No")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aDeclinedDriveAndOtherStopsAreNotThisCard() {
        #expect(BadPlanDraw.from(line: "") == nil)
        #expect(BadPlanDraw.from(line: "Okay, I won't touch anything.") == nil)
        #expect(BadPlanDraw.from(line: "I wasn't sure enough to click submit, so I stopped. Tell me how to go on.") == nil)
        #expect(BadPlanDraw.from(line: "I was going round in circles (clicking next), so I stopped.") == nil)
        #expect(BadPlanDraw.from(line: "I need Accessibility access to drive your Mac.") == nil)
    }
}
