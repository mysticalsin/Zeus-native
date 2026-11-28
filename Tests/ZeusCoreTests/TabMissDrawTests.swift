import Testing
@testable import ZeusCore

struct TabMissDrawTests {
    @Test func aChromeTabZeusCouldNotFindShowsMissing() throws {
        let plan = try #require(TabMissDraw.from(line: "I couldn't find that tab"))
        func cards(_ plan: TabMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Tab", "Missing"])
        #expect(plan.boltCaption(at: 0) == "Tab")
        #expect(plan.boltCaption(at: 100) == "Missing")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aNamedFindAndABlockedPageAreNotThisTab() {
        #expect(TabMissDraw.from(line: "") == nil)
        #expect(TabMissDraw.from(line: "I couldn't find that tab.") == nil)
        #expect(TabMissDraw.from(line: "I couldn't find Safari.") == nil)
        #expect(TabMissDraw.from(line: "No active Chrome tab") == nil)
        #expect(TabMissDraw.from(line: "The selected tab is no longer available.") == nil)
        #expect(TabMissDraw.from(line: "Chrome doesn't let extensions act on this page") == nil)
        #expect(TabMissDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
    }
}
