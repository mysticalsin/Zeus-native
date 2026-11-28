import Testing
@testable import ZeusCore

struct UnsureStopDrawTests {
    @Test func anUnsureStopShowsTheAction() throws {
        let plan = try #require(UnsureStopDraw.from(line: "I wasn't sure enough to click submit, so I stopped. Tell me how to go on."))
        func cards(_ plan: UnsureStopDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Unsure", "click submit"])
        #expect(plan.boltCaption(at: 0) == "Unsure")
        #expect(plan.boltCaption(at: 100) == "click submit")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankActionAndOtherStopsAreNotUnsure() {
        #expect(UnsureStopDraw.from(line: "") == nil)
        #expect(UnsureStopDraw.from(line: "I wasn't sure enough to , so I stopped. Tell me how to go on.") == nil)
        #expect(UnsureStopDraw.from(line: "I was going round in circles (clicking next), so I stopped.") == nil)
        #expect(UnsureStopDraw.from(line: "I stopped after 8 steps without finishing. Tell me how to go on.") == nil)
        #expect(UnsureStopDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
    }
}
