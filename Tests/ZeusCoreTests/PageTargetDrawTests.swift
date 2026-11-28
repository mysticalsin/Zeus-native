import Testing
@testable import ZeusCore

struct PageTargetDrawTests {
    @Test func aMissingPageTargetShowsTarget() throws {
        let plan = try #require(PageTargetDraw.from(line: "Read page.target before approving this action. Nothing was changed."))
        func cards(_ plan: PageTargetDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Page", "Target"])
        #expect(plan.boltCaption(at: 0) == "Page")
        #expect(plan.boltCaption(at: 100) == "Target")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aGoneDocumentAndAClosedTabAreNotThisTarget() {
        #expect(PageTargetDraw.from(line: "") == nil)
        #expect(PageTargetDraw.from(line: "The approved document is no longer available. Nothing was changed.") == nil)
        #expect(PageTargetDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
        #expect(PageTargetDraw.from(line: "The approved tab was closed. Nothing was changed.") == nil)
        #expect(PageTargetDraw.from(line: "The approved page navigated. Nothing was changed.") == nil)
        #expect(PageTargetDraw.from(line: "No active Chrome tab") == nil)
        #expect(PageTargetDraw.from(line: "Chrome couldn't identify the page. Nothing was changed.") == nil)
    }
}
