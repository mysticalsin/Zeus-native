import Testing
@testable import ZeusCore

struct SpotifyPressDrawTests {
    @Test func aSpotifyRequestZeusCouldNotPlayShowsNo() throws {
        let plan = try #require(SpotifyPressDraw.from(line: "Spotify is showing tides, but I couldn't press play."))
        func cards(_ plan: SpotifyPressDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Spotify", "No"])
        #expect(plan.request == "tides")
        #expect(plan.boltCaption(at: 0) == "Spotify")
        #expect(plan.boltCaption(at: 100) == "No")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aStartingRequestAndAMissingWindowAreNotThisPlay() {
        #expect(SpotifyPressDraw.from(line: "") == nil)
        #expect(SpotifyPressDraw.from(line: "Spotify is showing , but I couldn't press play.") == nil)
        #expect(SpotifyPressDraw.from(line: "Playing tides on Spotify.") == nil)
        #expect(SpotifyPressDraw.from(line: "Spotify isn't installed.") == nil)
        #expect(SpotifyPressDraw.from(line: "Spotify didn't open.") == nil)
        #expect(SpotifyPressDraw.from(line: "I couldn't find a Safari window called \u{201C}Notes\u{201D}.") == nil)
        #expect(SpotifyPressDraw.from(line: "I can't press \u{201C}Save\u{201D} directly.") == nil)
    }
}
