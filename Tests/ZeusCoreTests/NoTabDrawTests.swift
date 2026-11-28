import Testing
@testable import ZeusCore

struct NoTabDrawTests {
    @Test func chromeWithNoActiveTabShowsNone() throws {
        let plan = try #require(NoTabDraw.from(line: "No active Chrome tab"))
        func cards(_ plan: NoTabDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Chrome", "None"])
        #expect(plan.boltCaption(at: 0) == "Chrome")
        #expect(plan.boltCaption(at: 100) == "None")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingTabAndAnUnknownAssistantAreNotThisChrome() {
        #expect(NoTabDraw.from(line: "") == nil)
        #expect(NoTabDraw.from(line: "No active Chrome tab.") == nil)
        #expect(NoTabDraw.from(line: "I couldn't find that tab") == nil)
        #expect(NoTabDraw.from(line: "No assistant called dust") == nil)
        #expect(NoTabDraw.from(line: "The selected tab is no longer available.") == nil)
        #expect(NoTabDraw.from(line: "Chrome doesn't let extensions act on this page") == nil)
        #expect(NoTabDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
    }
}
