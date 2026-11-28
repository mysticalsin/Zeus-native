import Testing
@testable import ZeusCore

struct CloudVoiceDrawTests {
    private func cards(_ plan: CloudVoiceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallNamesNeitherCloudVoice() {
        let usual = CloudVoiceDraw.plan(openAI: "None", gemini: "None")
        #expect(cards(usual) == ["Cast", "OpenAI: None", "Gemini: None"])
        #expect(CloudVoiceAsk.line(openAI: "None", gemini: "None") == "OpenAI voice is none, and Gemini voice is none.")
        #expect(usual.boltCaption(at: 0) == "Cast")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Gemini: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(CloudVoiceAsk.line(openAI: "Onyx", gemini: "Kore") == "OpenAI voice is Onyx, and Gemini voice is Kore.")
        #expect(CloudVoiceAsk.line(openAI: "Ended", gemini: "Puck") == "OpenAI voice is ended, and Gemini voice is Puck.")
        #expect(cards(CloudVoiceDraw.plan(openAI: "Secret", gemini: "None")) == ["Cast", "Can't"])
        #expect(CloudVoiceAsk.line(openAI: "None", gemini: "Alex") == "I can't read the cloud voices.")
    }

    @Test func kokoroAndTheKeysStayOffThisAsk() {
        #expect(CloudVoiceAsk.matches("which cloud voices"))
        #expect(CloudVoiceAsk.matches("Hey Zeus, which openai voice?"))
        #expect(CloudVoiceAsk.matches("which gemini voice"))
        #expect(!CloudVoiceAsk.matches("which kokoro voice"))
        #expect(!CloudVoiceAsk.matches("which voice"))
        #expect(!CloudVoiceAsk.matches("is the openai voice key saved"))
        #expect(!CloudVoiceAsk.matches("which chat model"))
    }
}
