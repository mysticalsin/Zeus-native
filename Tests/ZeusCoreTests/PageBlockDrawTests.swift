import Testing
@testable import ZeusCore

struct PageBlockDrawTests {
    @Test func aPageChromeWillNotActOnShowsCant() throws {
        let plan = try #require(PageBlockDraw.from(line: "Chrome doesn't let extensions act on this page"))
        func cards(_ plan: PageBlockDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Page", "Can't"])
        #expect(plan.boltCaption(at: 0) == "Page")
        #expect(plan.boltCaption(at: 100) == "Can't")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anUntouchedPageAndAMissingDocumentAreNotThisBlock() {
        #expect(PageBlockDraw.from(line: "") == nil)
        #expect(PageBlockDraw.from(line: "Chrome doesn't let extensions act on this page.") == nil)
        #expect(PageBlockDraw.from(line: "Chrome couldn't identify the page. Nothing was changed.") == nil)
        #expect(PageBlockDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
        #expect(PageBlockDraw.from(line: "Zeus doesn't read private windows. Nothing was changed.") == nil)
        #expect(PageBlockDraw.from(line: "The selected tab is no longer available.") == nil)
        #expect(PageBlockDraw.from(line: "I can't ask you about that yet, so I left.") == nil)
    }
}
