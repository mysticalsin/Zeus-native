import Testing
@testable import ZeusCore

struct MusicLightsDrawTests {
    private func cards(_ plan: MusicLightsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFourLightsFollowWave() {
        let usual = MusicLightsDraw.plan(wave: "On", outline: "On", words: "On", sound: "Off")
        #expect(cards(usual) == ["Wave", "Wings: On", "Outline: On", "Words: On", "Sound: Off"])
        #expect(MusicLightsAsk.line(wave: "On", outline: "On", words: "On", sound: "Off") == "The music wave is on, the progress outline is on, word lights are on, and the sound reaction is off.")
        #expect(usual.boltCaption(at: 0) == "Wave")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Sound: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(MusicLightsAsk.line(wave: "Off", outline: "Off", words: "Off", sound: "On") == "The music wave is off, the progress outline is off, word lights are off, and the sound reaction is on.")
        #expect(cards(MusicLightsDraw.plan(wave: "Maybe", outline: "On", words: "On", sound: "Off")) == ["Wave", "Can't"])
        #expect(MusicLightsAsk.line(wave: "On", outline: "Loud", words: "On", sound: "Off") == "I can't read the music lights.")
    }

    @Test func theTrackAndTheEverydayLightsStayOffThisAsk() {
        #expect(MusicLightsAsk.matches("which music lights"))
        #expect(MusicLightsAsk.matches("Hey Zeus, how's the music wave set?"))
        #expect(MusicLightsAsk.matches("music light settings"))
        #expect(!MusicLightsAsk.matches("what's playing"))
        #expect(!MusicLightsAsk.matches("where's the music from"))
        #expect(!MusicLightsAsk.matches("which everyday lights"))
        #expect(!MusicLightsAsk.matches("how's the halo arm"))
    }
}
