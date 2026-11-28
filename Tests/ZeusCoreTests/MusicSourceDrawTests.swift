import Testing
@testable import ZeusCore

struct MusicSourceDrawTests {
    private func cards(_ plan: MusicSourceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let any = MusicSourceDraw.plan(word: "Any player")
        #expect(cards(any) == ["Source", "Any player"])
        #expect(MusicSourceAsk.line(word: "Any player") == "The notch follows the player that started last.")
        #expect(any.boltCaption(at: 0) == "Source")
        #expect(any.boltCaption(at: ExplainBeatSchedule.gap) == "Any player")
        #expect(any.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(MusicSourceAsk.line(word: "Music") == "The notch shows Music.")
        #expect(MusicSourceAsk.line(word: "Spotify") == "The notch shows Spotify.")
        #expect(cards(MusicSourceDraw.plan(word: "Banana")) == ["Source", "Can't"])
        #expect(MusicSourceAsk.line(word: "") == "I can't read the music source.")
    }

    @Test func theTrackAndTheOutputStayOffThisAsk() {
        #expect(MusicSourceAsk.matches("where's the music from"))
        #expect(MusicSourceAsk.matches("Hey Zeus, which player?"))
        #expect(MusicSourceAsk.matches("how's the music source"))
        #expect(!MusicSourceAsk.matches("what's playing"))
        #expect(!MusicSourceAsk.matches("where is the sound going"))
        #expect(!MusicSourceAsk.matches("who answers"))
        #expect(!MusicSourceAsk.matches("are my earbuds connected"))
    }
}
