import Testing
@testable import ZeusCore

struct LyricShowDrawTests {
    private func cards(_ plan: LyricShowDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func lyricsAndThePlayhead() {
        let usual = LyricShowDraw.plan(show: "Off", scrub: "Off")
        #expect(cards(usual) == ["Lyrics", "Show: Off", "Scrub: Off"])
        #expect(LyricShowAsk.line(show: "Off", scrub: "Off") == "Lyrics are hidden, and the playhead is not being dragged.")
        #expect(usual.boltCaption(at: 0) == "Lyrics")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Scrub: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(LyricShowAsk.line(show: "On", scrub: "Off") == "Lyrics are showing, and the playhead is not being dragged.")
        #expect(LyricShowAsk.line(show: "Off", scrub: "On") == "Lyrics are hidden, and the playhead is being dragged.")
        #expect(cards(LyricShowDraw.plan(show: "Yes", scrub: "Off")) == ["Lyrics", "Can't"])
        #expect(LyricShowAsk.line(show: "On", scrub: "Maybe") == "I can't read the lyrics.")
    }

    @Test func theTrackStaysOffThisAsk() {
        #expect(LyricShowAsk.matches("are the lyrics showing"))
        #expect(LyricShowAsk.matches("Hey Zeus, is the playhead being dragged?"))
        #expect(LyricShowAsk.matches("is the lyrics button on"))
        #expect(!LyricShowAsk.matches("what is playing"))
        #expect(!LyricShowAsk.matches("is shuffle on"))
        #expect(!LyricShowAsk.matches("how is playback set"))
        #expect(!LyricShowAsk.matches("is the chat window open"))
    }
}
