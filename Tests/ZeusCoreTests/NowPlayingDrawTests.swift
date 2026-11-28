import Testing
@testable import ZeusCore

struct NowPlayingDrawTests {
    @Test func aTrackDrawsPlayingThenTheTitleThenTheArtist() {
        let plan = NowPlayingDraw.plan(title: "Kind of Blue", artist: "Miles Davis", playing: true)
        let cards = plan?.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Playing", "Kind of Blue", "Miles Davis"])
        #expect(plan?.boltCaption(at: 0) == "Playing")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Kind of Blue")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Miles Davis")
        #expect(plan?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(NowPlayingAsk.line(title: "Kind of Blue", artist: "Miles Davis", playing: true) == "Playing Kind of Blue by Miles Davis.")
    }

    @Test func aPauseDropsTheArtistWhenItIsBlankAndABlankTitleIsNotDrawn() {
        let paused = NowPlayingDraw.plan(title: "So What", artist: "  ", playing: false)
        let cards = paused?.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Paused", "So What"])
        #expect(NowPlayingAsk.line(title: "So What", artist: "", playing: false) == "Paused on So What.")
        #expect(NowPlayingDraw.plan(title: "  ", artist: "Miles Davis", playing: true) == nil)
        #expect(NowPlayingAsk.line(title: "\n", artist: "Miles Davis", playing: true) == nil)
    }

    @Test func nothingPlayingDrawsNothingAndAPlayCommandIsNotTheAsk() {
        let idle = NowPlayingDraw.nothing()
        let cards = idle.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Playing", "Nothing"])
        #expect(idle.boltCaption(at: ExplainBeatSchedule.gap) == "Nothing")
        #expect(NowPlayingAsk.nothing == "Nothing is playing.")
        #expect(NowPlayingAsk.matches("what's playing"))
        #expect(NowPlayingAsk.matches("Hey Zeus, what song is this?"))
        #expect(NowPlayingAsk.matches("what am I listening to"))
        #expect(!NowPlayingAsk.matches("play Kind of Blue"))
        #expect(!NowPlayingAsk.matches("next track"))
    }
}
