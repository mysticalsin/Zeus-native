import Testing
@testable import ZeusCore

struct ScrollRangeDrawTests {
    @Test func aScrollOutOfRangeShowsRange() throws {
        let plan = try #require(ScrollRangeDraw.from(line: "That scroll amount is out of range."))
        func cards(_ plan: ScrollRangeDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Scroll", "Range"])
        #expect(plan.boltCaption(at: 0) == "Scroll")
        #expect(plan.boltCaption(at: 100) == "Range")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aStaleScreenAndAnEndpointAreNotThisScroll() {
        #expect(ScrollRangeDraw.from(line: "") == nil)
        #expect(ScrollRangeDraw.from(line: "That screen changed before I got to s3:e7.") == nil)
        #expect(ScrollRangeDraw.from(line: "The Any LLM endpoint isn't set up.") == nil)
        #expect(ScrollRangeDraw.from(line: "The Any LLM endpoint didn't answer.") == nil)
        #expect(ScrollRangeDraw.from(line: "I don't know the key return.") == nil)
        #expect(ScrollRangeDraw.from(line: "Physical pointer control is off, so I can't move to or click that target.") == nil)
    }
}
