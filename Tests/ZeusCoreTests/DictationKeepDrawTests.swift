import Testing
@testable import ZeusCore

struct DictationKeepDrawTests {
    private func cards(_ plan: DictationKeepDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSpanFollowsKeep() {
        let usual = DictationKeepDraw.plan(span: "30 days")
        #expect(cards(usual) == ["Keep", "For: 30 days"])
        #expect(DictationKeepAsk.line(span: "30 days") == "Dictation is kept for 30 days.")
        #expect(usual.boltCaption(at: 0) == "Keep")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "For: 30 days")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(DictationKeepAsk.line(span: "Forever") == "Dictation is kept forever.")
        #expect(DictationKeepAsk.line(span: "7 days") == "Dictation is kept for 7 days.")
        #expect(cards(DictationKeepDraw.plan(span: "14 days")) == ["Keep", "For: 14 days"])
        #expect(cards(DictationKeepDraw.plan(span: "90 days")) == ["Keep", "For: 90 days"])
        #expect(cards(DictationKeepDraw.plan(span: "Soon")) == ["Keep", "Can't"])
        #expect(DictationKeepAsk.line(span: "0 days") == "I can't read how long dictation is kept.")
    }

    @Test func theDictationSoundStaysOffThisAsk() {
        #expect(DictationKeepAsk.matches("how long is dictation kept"))
        #expect(DictationKeepAsk.matches("Hey Zeus, is dictation kept forever?"))
        #expect(DictationKeepAsk.matches("dictation history settings"))
        #expect(!DictationKeepAsk.matches("what's the dictation sound"))
        #expect(!DictationKeepAsk.matches("how's dictation set"))
        #expect(!DictationKeepAsk.matches("which language packs"))
        #expect(!DictationKeepAsk.matches("what's the home backdrop"))
    }
}
