import Testing
@testable import ZeusCore

struct DictationWordsDrawTests {
    private func cards(_ plan: DictationWordsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneWordDrawsTheCountThenToday() {
        let plan = DictationWordsDraw.plan(count: 1)
        #expect(plan.map(cards) == ["Words", "1", "Today"])
        #expect(DictationWordsAsk.line(count: 1) == "You dictated 1 word today.")
        #expect(plan?.boltCaption(at: 0) == "Words")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "1")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Today")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(DictationWordsDraw.plan(count: 0) == nil)
        #expect(cards(DictationWordsDraw.none()) == ["Words", "None"])
        #expect(DictationWordsAsk.none == "No words dictated today.")
        #expect(DictationWordsAsk.line(count: 1) == "You dictated 1 word today.")
    }

    @Test func severalWordsStayOffTheRoundsAsk() {
        let plan = DictationWordsDraw.plan(count: 40)
        #expect(plan.map(cards) == ["Words", "40", "Today"])
        #expect(DictationWordsAsk.line(count: 40) == "You dictated 40 words today.")
        #expect(DictationWordsAsk.matches("how many words today"))
        #expect(DictationWordsAsk.matches("Hey Zeus, how many words did I dictate?"))
        #expect(DictationWordsAsk.matches("dictation words"))
        #expect(!DictationWordsAsk.matches("how many rounds today"))
        #expect(!DictationWordsAsk.matches("how many clips"))
        #expect(!DictationWordsAsk.matches("read my note"))
        #expect(!DictationWordsAsk.matches("how many words on my clipboard"))
        #expect(!DictationWordsAsk.matches("is caps lock on"))
    }
}
