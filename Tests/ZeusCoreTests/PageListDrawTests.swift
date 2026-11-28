import Testing
@testable import ZeusCore

struct PageListDrawTests {
    @Test func anUnreadPageListShowsUnread() throws {
        let plan = try #require(PageListDraw.from(line: "The separate browser's page list couldn't be read."))
        func cards(_ plan: PageListDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Pages", "Unread"])
        #expect(plan.boltCaption(at: 0) == "Pages")
        #expect(plan.boltCaption(at: 100) == "Unread")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aScrollAndAMissingEndpointAreNotThisList() {
        #expect(PageListDraw.from(line: "") == nil)
        #expect(PageListDraw.from(line: "That scroll amount is out of range.") == nil)
        #expect(PageListDraw.from(line: "The Any LLM endpoint isn't set up.") == nil)
        #expect(PageListDraw.from(line: "the separate browser isn't set up yet. Open Settings, Features.") == nil)
        #expect(PageListDraw.from(line: "The separate browser stopped.") == nil)
        #expect(PageListDraw.from(line: "I looked in your vault and didn't find notes about tides.") == nil)
    }
}
