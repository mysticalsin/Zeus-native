import Testing
@testable import ZeusCore

struct MenuMissDrawTests {
    @Test func aBeamerMenuThatDidNotRespondShowsItsName() throws {
        let plan = try #require(MenuMissDraw.from(line: "Beamer's menu didn't respond to \u{201C}Pause\u{201D}."))
        func cards(_ plan: MenuMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Menu", "\u{201C}Pause\u{201D}"])
        #expect(plan.boltCaption(at: 0) == "Menu")
        #expect(plan.boltCaption(at: 100) == "\u{201C}Pause\u{201D}")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aSilentBeamerAndASpotifyMissAreNotThisMenu() {
        #expect(MenuMissDraw.from(line: "") == nil)
        #expect(MenuMissDraw.from(line: "Beamer's menu didn't respond to .") == nil)
        #expect(MenuMissDraw.from(line: "Beamer didn't answer.") == nil)
        #expect(MenuMissDraw.from(line: "Beamer isn't running. Say start Beamer first.") == nil)
        #expect(MenuMissDraw.from(line: "Spotify is showing tides, but I couldn't press play.") == nil)
        #expect(MenuMissDraw.from(line: "I couldn't find a Safari window called \u{201C}Notes\u{201D}.") == nil)
        #expect(MenuMissDraw.from(line: "I can't press \u{201C}Save\u{201D} directly.") == nil)
    }
}
