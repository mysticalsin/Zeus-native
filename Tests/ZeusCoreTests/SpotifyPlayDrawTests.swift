import Testing
@testable import ZeusCore

struct SpotifyPlayDrawTests {
    @Test func aRequestAndAResumeNameSpotify() throws {
        let request = try #require(SpotifyPlayDraw.from(summary: "Spotify: Kind of Blue"))
        let resume = try #require(SpotifyPlayDraw.from(summary: "Play Spotify"))
        func cards(_ plan: SpotifyPlayDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(request) == ["Spotify", "Kind of Blue"])
        #expect(request.boltCaption(at: 0) == "Spotify")
        #expect(request.boltCaption(at: 100) == "Kind of Blue")
        #expect(request.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(request.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(resume) == ["Spotify", "Playing"])
        #expect(resume.boltCaption(at: 100) == "Playing")
    }

    @Test func aBlankRequestAndOtherSummariesAreNotDrawn() {
        #expect(SpotifyPlayDraw.from(summary: "Spotify: ") == nil)
        #expect(SpotifyPlayDraw.from(summary: "Spotify:   ") == nil)
        #expect(SpotifyPlayDraw.plan(request: " ") == nil)
        #expect(SpotifyPlayDraw.from(summary: "Spotify isn't installed") == nil)
        #expect(SpotifyPlayDraw.from(summary: "Play") == nil)
        #expect(SpotifyPlayDraw.from(summary: "Next track") == nil)
        #expect(SpotifyPlayDraw.from(summary: "Pause") == nil)
    }
}
