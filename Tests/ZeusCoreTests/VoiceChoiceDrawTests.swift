import Testing
@testable import ZeusCore

struct VoiceChoiceDrawTests {
    private func cards(_ plan: VoiceChoiceDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuChoiceIsTheSecondCard() {
        let automatic = VoiceChoiceDraw.plan(word: VoiceChoiceAsk.automatic)
        #expect(cards(automatic) == ["Voice", "Automatic (best working voice)"])
        #expect(VoiceChoiceAsk.line(word: VoiceChoiceAsk.automatic) == "Zeus speaks with the automatic voice.")
        #expect(automatic.boltCaption(at: 0) == "Voice")
        #expect(automatic.boltCaption(at: ExplainBeatSchedule.gap) == "Automatic (best working voice)")
        #expect(automatic.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(cards(VoiceChoiceDraw.plan(word: "ElevenLabs")) == ["Voice", "ElevenLabs"])
        #expect(VoiceChoiceAsk.line(word: "ElevenLabs") == "Zeus speaks with ElevenLabs.")
        #expect(cards(VoiceChoiceDraw.plan(word: "Banana")) == ["Voice", "Can't"])
        #expect(VoiceChoiceAsk.line(word: "") == "I can't read the voice.")
    }

    @Test func beamerAndFaceStayOffThisAsk() {
        #expect(VoiceChoiceAsk.matches("which voice is this"))
        #expect(VoiceChoiceAsk.matches("Hey Zeus, what's the voice?"))
        #expect(VoiceChoiceAsk.matches("how's the voice"))
        #expect(!VoiceChoiceAsk.matches("where's my keyboard"))
        #expect(!VoiceChoiceAsk.matches("how's face presence"))
        #expect(!VoiceChoiceAsk.matches("is hey zeus on"))
        #expect(!VoiceChoiceAsk.matches("is dictation on"))
        #expect(!VoiceChoiceAsk.matches("how's the heat"))
    }
}
