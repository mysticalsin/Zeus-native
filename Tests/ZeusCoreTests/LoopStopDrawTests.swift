import Testing
@testable import ZeusCore

struct LoopStopDrawTests {
    @Test func aLoopShowsTheAction() throws {
        let plan = try #require(LoopStopDraw.from(line: "I was going round in circles (clicking next), so I stopped."))
        func cards(_ plan: LoopStopDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Loop", "clicking next"])
        #expect(plan.boltCaption(at: 0) == "Loop")
        #expect(plan.boltCaption(at: 100) == "clicking next")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankActionAndOtherStopsAreNotALoop() {
        #expect(LoopStopDraw.from(line: "") == nil)
        #expect(LoopStopDraw.from(line: "I was going round in circles (), so I stopped.") == nil)
        #expect(LoopStopDraw.from(line: "I stopped after 8 steps without finishing. Tell me how to go on.") == nil)
        #expect(LoopStopDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
        #expect(LoopStopDraw.from(line: "Stopped.") == nil)
    }
}
