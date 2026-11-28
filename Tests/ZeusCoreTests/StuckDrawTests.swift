import Testing
@testable import ZeusCore

struct StuckDrawTests {
    @Test func aStuckAgentShowsTheReason() throws {
        let plan = try #require(StuckDraw.from(line: "I'm stuck: the login form."))
        func cards(_ plan: StuckDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Stuck", "the login form."])
        #expect(plan.boltCaption(at: 0) == "Stuck")
        #expect(plan.boltCaption(at: 100) == "the login form.")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankReasonAndOtherStopsAreNotStuck() {
        #expect(StuckDraw.from(line: "") == nil)
        #expect(StuckDraw.from(line: "I'm stuck:") == nil)
        #expect(StuckDraw.from(line: "That plan didn't make sense, so I left it.") == nil)
        #expect(StuckDraw.from(line: "I wasn't sure enough to click submit, so I stopped. Tell me how to go on.") == nil)
        #expect(StuckDraw.from(line: "I was going round in circles (clicking next), so I stopped.") == nil)
    }
}
