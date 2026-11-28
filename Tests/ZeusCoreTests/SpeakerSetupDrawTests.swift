import Testing
@testable import ZeusCore

struct SpeakerSetupDrawTests {
    private func cards(_ plan: SpeakerSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func apartLiveAndNamesFollowSpeakers() {
        let usual = SpeakerSetupDraw.plan(apart: "Off", live: "Off", names: "Off")
        #expect(cards(usual) == ["Speakers", "Apart: Off", "Live: Off", "Names: Off"])
        #expect(SpeakerSetupAsk.line(apart: "Off", live: "Off", names: "Off") == "The voice model is not downloaded, the live model is not downloaded, and names from the call window are off.")
        #expect(usual.boltCaption(at: 0) == "Speakers")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Names: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(SpeakerSetupAsk.line(apart: "Ready", live: "Downloading", names: "On") == "The voice model is ready, the live model is downloading, and names from the call window are on.")
        #expect(SpeakerSetupAsk.line(apart: "Failed", live: "Ready", names: "Off") == "The voice model failed, the live model is ready, and names from the call window are off.")
        #expect(cards(SpeakerSetupDraw.plan(apart: "Ready", live: "Failed", names: "On")) == ["Speakers", "Apart: Ready", "Live: Failed", "Names: On"])
        #expect(cards(SpeakerSetupDraw.plan(apart: "Missing", live: "Off", names: "Off")) == ["Speakers", "Can't"])
        #expect(SpeakerSetupAsk.line(apart: "Off", live: "Off", names: "Maybe") == "I can't read speaker recognition.")
    }

    @Test func theChosenVoiceStaysOffThisAsk() {
        #expect(SpeakerSetupAsk.matches("how's speaker recognition set"))
        #expect(SpeakerSetupAsk.matches("Hey Zeus, can scribe tell voices apart?"))
        #expect(SpeakerSetupAsk.matches("speaker recognition settings"))
        #expect(!SpeakerSetupAsk.matches("which voice"))
        #expect(!SpeakerSetupAsk.matches("how's the voice styled"))
        #expect(!SpeakerSetupAsk.matches("how's scribe set"))
        #expect(!SpeakerSetupAsk.matches("which language packs"))
    }
}
