import Testing
@testable import ZeusCore

struct ScreenStaleDrawTests {
    @Test func aScreenThatChangedShowsStale() throws {
        let plan = try #require(ScreenStaleDraw.from(line: "That screen changed before I got to s3:e7."))
        func cards(_ plan: ScreenStaleDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Screen", "Stale"])
        #expect(plan.boltCaption(at: 0) == "Screen")
        #expect(plan.boltCaption(at: 100) == "Stale")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aChromePageAndASavedReportAreNotThisScreen() {
        #expect(ScreenStaleDraw.from(line: "") == nil)
        #expect(ScreenStaleDraw.from(line: "That screen changed before I got to .") == nil)
        #expect(ScreenStaleDraw.from(line: "Chrome couldn't identify the page. Nothing was changed.") == nil)
        #expect(ScreenStaleDraw.from(line: "The page kept changing under me, so I stopped without touching anything else.") == nil)
        #expect(ScreenStaleDraw.from(line: "Done. The report is saved. I couldn't save the report.") == nil)
    }
}
