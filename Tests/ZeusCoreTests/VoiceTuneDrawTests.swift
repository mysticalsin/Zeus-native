import Testing
@testable import ZeusCore

struct VoiceTuneDrawTests {
    private func cards(_ plan: VoiceTuneDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesStudioAndTheDesignedPace() {
        let usual = VoiceTuneDraw.plan(quality: "Studio", effect: "75", pace: "0.88")
        #expect(cards(usual) == ["Tune", "Quality: Studio", "Effect: 75%", "Pace: 0.88"])
        #expect(VoiceTuneAsk.line(quality: "Studio", effect: "75", pace: "0.88") == "Voice quality is Studio, the effect is 75 percent, and Kokoro pace is 0.88 times.")
        #expect(usual.boltCaption(at: 0) == "Tune")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Pace: 0.88")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(VoiceTuneAsk.line(quality: "Fastest", effect: "0", pace: "1.30") == "Voice quality is Fastest, the effect is 0 percent, and Kokoro pace is 1.30 times.")
        #expect(cards(VoiceTuneDraw.plan(quality: "Fastest", effect: "100", pace: "0.70")) == ["Tune", "Quality: Fastest", "Effect: 100%", "Pace: 0.70"])
        #expect(cards(VoiceTuneDraw.plan(quality: "Rich", effect: "75", pace: "0.88")) == ["Tune", "Can't"])
        #expect(VoiceTuneAsk.line(quality: "Studio", effect: "75", pace: "0.880") == "I can't read how the voice is tuned.")
    }

    @Test func theChosenVoiceStaysOffThisAsk() {
        #expect(VoiceTuneAsk.matches("how is the voice tuned"))
        #expect(VoiceTuneAsk.matches("Hey Zeus, what is the voice quality?"))
        #expect(VoiceTuneAsk.matches("how fast is kokoro"))
        #expect(!VoiceTuneAsk.matches("which voice"))
        #expect(!VoiceTuneAsk.matches("how is the voice styled"))
        #expect(!VoiceTuneAsk.matches("which voice keys are saved"))
        #expect(!VoiceTuneAsk.matches("how are updates set"))
    }
}
