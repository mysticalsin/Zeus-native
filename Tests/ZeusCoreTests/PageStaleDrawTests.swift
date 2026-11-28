import Testing
@testable import ZeusCore

struct PageStaleDrawTests {
    @Test func aPageThatKeptChangingShowsChanged() throws {
        let plan = try #require(PageStaleDraw.from(line: PageStaleDraw.line))
        func cards(_ plan: PageStaleDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Page", "Changed"])
        #expect(plan.boltCaption(at: 0) == "Page")
        #expect(plan.boltCaption(at: 100) == "Changed")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aStoppedAgentAndOtherLinesAreNotThisCard() {
        #expect(PageStaleDraw.from(line: "") == nil)
        #expect(PageStaleDraw.from(line: "Stopped.") == nil)
        #expect(PageStaleDraw.from(line: "I'm stuck: the login.") == nil)
        #expect(PageStaleDraw.from(line: "Okay, I won't send it.") == nil)
        #expect(PageStaleDraw.from(line: "I couldn't make sense of that browser step.") == nil)
    }
}
