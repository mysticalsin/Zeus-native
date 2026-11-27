import Testing
@testable import ZeusCore

struct PageUntouchedDrawTests {
    @Test func aPageZeusLeftAloneShowsWhy() throws {
        let cases: [(String, [String])] = [
            ("Chrome couldn't identify the page. Nothing was changed.", ["Chrome", "Untouched"]),
            ("The approved page navigated. Nothing was changed.", ["Page", "Moved"]),
            ("Zeus doesn't read private windows. Nothing was changed.", ["Private", "Off"]),
            ("The approved tab was closed. Nothing was changed.", ["Tab", "Closed"]),
            ("The approved page reloaded. Nothing was changed.", ["Page", "Reloaded"]),
            ("The active tab or approved page changed. Nothing was changed.", ["Tab", "Switched"]),
            ("The selected tab is no longer available.", ["Tab", "Gone"]),
        ]
        func cards(_ plan: PageUntouchedDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        let first = try #require(PageUntouchedDraw.from(line: cases[0].0))
        #expect(cards(first) == cases[0].1)
        #expect(first.boltCaption(at: 0) == "Chrome")
        #expect(first.boltCaption(at: 100) == "Untouched")
        #expect(first.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(first.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        for (line, expected) in cases.dropFirst() {
            let plan = try #require(PageUntouchedDraw.from(line: line))
            #expect(cards(plan) == expected)
        }
    }

    @Test func aChangingAgentPageIsNotThisUntouchedPage() {
        #expect(PageUntouchedDraw.from(line: "") == nil)
        #expect(PageUntouchedDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
        #expect(PageUntouchedDraw.from(line: "Read page.target before approving this action. Nothing was changed.") == nil)
        #expect(PageUntouchedDraw.from(line: "The approved document is unavailable. Nothing was changed.") == nil)
        #expect(PageUntouchedDraw.from(line: "No calendar accepts new events. Add one in Calendar.") == nil)
    }
}
