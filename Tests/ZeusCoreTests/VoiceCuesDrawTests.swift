import Testing
@testable import ZeusCore

struct VoiceCuesDrawTests {
    private func cards(_ plan: VoiceCuesDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theCuesThatPlayFollowVoice() {
        let all = VoiceCuesDraw.plan(words: ["Listening", "Stopped", "Answer", "Error"])
        #expect(cards(all) == ["Voice", "Listening", "Stopped", "Answer", "Error"])
        #expect(VoiceCuesAsk.line(words: ["Listening", "Stopped", "Answer", "Error"]) == "Voice cues play Listening, Stopped, Answer, and Error.")
        #expect(all.boltCaption(at: 0) == "Voice")
        #expect(all.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Error")
        #expect(all.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(cards(VoiceCuesDraw.plan(words: [])) == ["Voice", "None"])
        #expect(VoiceCuesAsk.line(words: []) == "Voice cues are off.")
        #expect(VoiceCuesAsk.line(words: ["Listening"]) == "Voice cues play Listening.")
        #expect(cards(VoiceCuesDraw.plan(words: ["Error", "Listening"])) == ["Voice", "Can't"])
        #expect(VoiceCuesAsk.line(words: ["Beep"]) == "I can't read the voice cues.")
    }

    @Test func theChosenVoiceAndTheCueStylesStayOffThisAsk() {
        #expect(VoiceCuesAsk.matches("which voice cues"))
        #expect(VoiceCuesAsk.matches("Hey Zeus, how's the voice cues?"))
        #expect(VoiceCuesAsk.matches("voice cues"))
        #expect(!VoiceCuesAsk.matches("which voice is this"))
        #expect(!VoiceCuesAsk.matches("what are the cue sounds"))
        #expect(!VoiceCuesAsk.matches("how's dictation set"))
        #expect(!VoiceCuesAsk.matches("is Hey Zeus on"))
    }
}
