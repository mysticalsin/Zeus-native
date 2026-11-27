import Testing
@testable import ZeusCore

struct ClickLeftDrawTests {
    @Test func aClickLeftAloneShowsLeft() throws {
        let plan = try #require(ClickLeftDraw.from(line: "Okay, I left it."))
        func cards(_ plan: ClickLeftDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Click", "Left"])
        #expect(plan.boltCaption(at: 0) == "Click")
        #expect(plan.boltCaption(at: 100) == "Left")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aTabLeftOpenAndAMissingGoalAreNotThisClick() {
        #expect(ClickLeftDraw.from(line: "") == nil)
        #expect(ClickLeftDraw.from(line: "Okay, I left it open.") == nil)
        #expect(ClickLeftDraw.from(line: "Okay, I won't touch anything.") == nil)
        #expect(ClickLeftDraw.from(line: "Okay, I didn't click submit. I've stopped there.") == nil)
        #expect(ClickLeftDraw.from(line: "there was no goal.") == nil)
    }
}
