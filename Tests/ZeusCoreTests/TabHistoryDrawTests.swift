import Testing
@testable import ZeusCore

struct TabHistoryDrawTests {
    @Test func noEarlierOrLaterPageShowsTheEdge() throws {
        let back = try #require(TabHistoryDraw.from(line: "There's no earlier page in this tab."))
        let forward = try #require(TabHistoryDraw.from(line: "There's no later page in this tab."))
        func cards(_ plan: TabHistoryDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(back) == ["Back", "Start"])
        #expect(back.boltCaption(at: 0) == "Back")
        #expect(back.boltCaption(at: 100) == "Start")
        #expect(back.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(back.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(forward) == ["Forward", "End"])
        #expect(forward.boltCaption(at: 0) == "Forward")
        #expect(forward.boltCaption(at: 100) == "End")
    }

    @Test func aChangingPageAndALeftClickAreNotThisHistory() {
        #expect(TabHistoryDraw.from(line: "") == nil)
        #expect(TabHistoryDraw.from(line: "There's no page to go to in that direction.") == nil)
        #expect(TabHistoryDraw.from(line: "There's no earlier page.") == nil)
        #expect(TabHistoryDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
        #expect(TabHistoryDraw.from(line: "Okay, I left it.") == nil)
    }
}
