import Testing
@testable import ZeusCore

struct VocabSetupDrawTests {
    private func cards(_ plan: VocabSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoVocabulary() {
        let usual = VocabSetupDraw.plan(words: "0", fixes: "0")
        #expect(cards(usual) == ["Terms", "Words: 0", "Fixes: 0"])
        #expect(VocabSetupAsk.line(words: "0", fixes: "0") == "No vocabulary words, and no replacements.")
        #expect(usual.boltCaption(at: 0) == "Terms")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Fixes: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(VocabSetupAsk.line(words: "1", fixes: "1") == "1 vocabulary word, and 1 replacement.")
        #expect(VocabSetupAsk.line(words: "3", fixes: "2") == "3 vocabulary words, and 2 replacements.")
        #expect(cards(VocabSetupDraw.plan(words: "4", fixes: "0")) == ["Terms", "Words: 4", "Fixes: 0"])
        #expect(cards(VocabSetupDraw.plan(words: "00", fixes: "0")) == ["Terms", "Can't"])
        #expect(VocabSetupAsk.line(words: "Zeus", fixes: "0") == "I can't read the dictation vocabulary.")
    }

    @Test func todaysWordCountStaysOffThisAsk() {
        #expect(VocabSetupAsk.matches("how is the vocabulary set"))
        #expect(VocabSetupAsk.matches("Hey Zeus, how many vocabulary words?"))
        #expect(VocabSetupAsk.matches("dictation vocabulary settings"))
        #expect(!VocabSetupAsk.matches("how many words today"))
        #expect(!VocabSetupAsk.matches("which dictation microphone"))
        #expect(!VocabSetupAsk.matches("how is the separate browser set"))
        #expect(!VocabSetupAsk.matches("which apps does tiling leave out"))
    }
}
