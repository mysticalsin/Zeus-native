import Testing
@testable import ZeusCore

struct VoiceKeyDrawTests {
    private func cards(_ plan: VoiceKeyDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoVoiceKeys() {
        let usual = VoiceKeyDraw.plan(eleven: "None", openAI: "None", gemini: "None")
        #expect(cards(usual) == ["Keys", "Eleven: None", "OpenAI: None", "Gemini: None"])
        #expect(VoiceKeyAsk.line(eleven: "None", openAI: "None", gemini: "None") == "ElevenLabs has no key, OpenAI has no key, and Gemini has no key.")
        #expect(usual.boltCaption(at: 0) == "Keys")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Gemini: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(VoiceKeyAsk.line(eleven: "Saved", openAI: "None", gemini: "Saved") == "ElevenLabs has a saved key, OpenAI has no key, and Gemini has a saved key.")
        #expect(cards(VoiceKeyDraw.plan(eleven: "Saved", openAI: "Saved", gemini: "Saved")) == ["Keys", "Eleven: Saved", "OpenAI: Saved", "Gemini: Saved"])
        #expect(cards(VoiceKeyDraw.plan(eleven: "Missing", openAI: "None", gemini: "None")) == ["Keys", "Can't"])
        #expect(VoiceKeyAsk.line(eleven: "sk-test", openAI: "None", gemini: "None") == "I can't read the voice keys.")
    }

    @Test func theChosenVoiceStaysOffThisAsk() {
        #expect(VoiceKeyAsk.matches("which voice keys are saved"))
        #expect(VoiceKeyAsk.matches("Hey Zeus, is the elevenlabs key saved?"))
        #expect(VoiceKeyAsk.matches("voice key settings"))
        #expect(!VoiceKeyAsk.matches("which voice"))
        #expect(!VoiceKeyAsk.matches("how is the voice styled"))
        #expect(!VoiceKeyAsk.matches("is a jev key saved"))
        #expect(!VoiceKeyAsk.matches("how is the world clock set"))
    }
}
