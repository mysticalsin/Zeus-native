import Testing
@testable import ZeusCore

struct DictationLiveDrawTests {
    private func cards(_ plan: DictationLiveDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func listeningDrawsTheModeAndLeavesTheWordsOff() {
        let plan = DictationLiveDraw.plan(seen: true, phase: "Listening", mode: "Voice")
        #expect(cards(plan) == ["Dictation", "Listening", "Voice"])
        #expect(DictationLiveAsk.line(seen: true, phase: "Listening", mode: "Voice") == "Dictation is listening in Voice.")
        #expect(plan.boltCaption(at: 0) == "Dictation")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Listening")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Voice")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        let secret = "the password is swordfish"
        #expect(!cards(plan).joined(separator: " ").contains(secret))
        #expect(cards(DictationLiveDraw.plan(seen: false, phase: "Listening", mode: "Voice")) == ["Dictation", "Can't"])
        #expect(DictationLiveAsk.line(seen: false, phase: "Listening", mode: "Voice") == "I can't read dictation.")
    }

    @Test func eachPagePhaseHasItsOwnWord() {
        #expect(cards(DictationLiveDraw.plan(seen: true, phase: "Ready", mode: "Voice")) == ["Dictation", "Ready"])
        #expect(DictationLiveAsk.line(seen: true, phase: "Ready", mode: "Voice") == "Dictation is ready.")
        #expect(DictationLiveAsk.line(seen: true, phase: "Transcribing", mode: "") == "Dictation is transcribing on your Mac.")
        #expect(cards(DictationLiveDraw.plan(seen: true, phase: "Polishing", mode: "Clean")) == ["Dictation", "Polishing", "Clean"])
        #expect(DictationLiveAsk.line(seen: true, phase: "Polishing", mode: "Clean") == "Dictation is polishing with Clean.")
        let failed = DictationLiveDraw.plan(seen: true, phase: "Failed", mode: "the password is swordfish")
        #expect(cards(failed) == ["Dictation", "Failed"])
        #expect(DictationLiveAsk.line(seen: true, phase: "Failed", mode: "the password is swordfish") == "Dictation didn't finish.")
        #expect(DictationLiveAsk.matches("is dictation on"))
        #expect(DictationLiveAsk.matches("Hey Zeus, how's dictation?"))
        #expect(!DictationLiveAsk.matches("how many words today"))
        #expect(!DictationLiveAsk.matches("are you recording"))
        #expect(!DictationLiveAsk.matches("where is the sound going"))
        #expect(!DictationLiveAsk.matches("how's the lid"))
    }
}
