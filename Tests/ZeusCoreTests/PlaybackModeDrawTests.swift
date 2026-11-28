import Testing
@testable import ZeusCore

struct PlaybackModeDrawTests {
    private func cards(_ plan: PlaybackModeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func unreadModesStayUnknown() {
        let usual = PlaybackModeDraw.plan(shuffle: "Unknown", repeatMode: "Unknown")
        #expect(cards(usual) == ["Modes", "Shuffle: Unknown", "Repeat: Unknown"])
        #expect(PlaybackModeAsk.line(shuffle: "Unknown", repeatMode: "Unknown") == "Shuffle has not been read, and repeat has not been read.")
        #expect(usual.boltCaption(at: 0) == "Modes")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Repeat: Unknown")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PlaybackModeAsk.line(shuffle: "On", repeatMode: "Off") == "Shuffle is on, and repeat is off.")
        #expect(PlaybackModeAsk.line(shuffle: "Off", repeatMode: "One") == "Shuffle is off, and repeat is one song.")
        #expect(PlaybackModeAsk.line(shuffle: "Off", repeatMode: "All") == "Shuffle is off, and repeat is all.")
        #expect(cards(PlaybackModeDraw.plan(shuffle: "Yes", repeatMode: "Off")) == ["Modes", "Can't"])
        #expect(PlaybackModeAsk.line(shuffle: "On", repeatMode: "Songs") == "I can't read shuffle and repeat.")
    }

    @Test func theTrackStaysOffThisAsk() {
        #expect(PlaybackModeAsk.matches("is shuffle on"))
        #expect(PlaybackModeAsk.matches("Hey Zeus, which repeat mode?"))
        #expect(PlaybackModeAsk.matches("how is playback set"))
        #expect(!PlaybackModeAsk.matches("what is playing"))
        #expect(!PlaybackModeAsk.matches("which player"))
        #expect(!PlaybackModeAsk.matches("how long is a focus round"))
        #expect(!PlaybackModeAsk.matches("which models does zeus use"))
    }
}
