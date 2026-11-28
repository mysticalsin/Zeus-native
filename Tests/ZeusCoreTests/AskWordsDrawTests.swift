import Testing
@testable import ZeusCore

struct AskWordsDrawTests {
    private func cards(_ plan: AskWordsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallAsksOnlyForTheBuiltInWords() {
        let usual = AskWordsDraw.plan(extra: "0", builtIn: "Always")
        #expect(cards(usual) == ["Ask", "Extra: 0", "Built-in: Always"])
        #expect(AskWordsAsk.line(extra: "0", builtIn: "Always") == "No extra words always ask, and buying, sending, deleting, and posting always ask.")
        #expect(usual.boltCaption(at: 0) == "Ask")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Built-in: Always")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(AskWordsAsk.extraCount(" apply, invite , ") == 2)
        #expect(AskWordsAsk.extraCount("") == 0)
        #expect(AskWordsAsk.line(extra: "1", builtIn: "Always") == "1 extra word always asks, and buying, sending, deleting, and posting always ask.")
        #expect(cards(AskWordsDraw.plan(extra: "3", builtIn: "Always")) == ["Ask", "Extra: 3", "Built-in: Always"])
        #expect(cards(AskWordsDraw.plan(extra: "0", builtIn: "Sometimes")) == ["Ask", "Can't"])
        #expect(AskWordsAsk.line(extra: "apply", builtIn: "Always") == "I can't read what always asks.")
    }

    @Test func theBrowserChoiceStaysOffThisAsk() {
        #expect(AskWordsAsk.matches("what always asks"))
        #expect(AskWordsAsk.matches("Hey Zeus, do extra words always ask?"))
        #expect(AskWordsAsk.matches("browser ask settings"))
        #expect(!AskWordsAsk.matches("how is the browser agent set"))
        #expect(!AskWordsAsk.matches("which browser does the agent use"))
        #expect(!AskWordsAsk.matches("how is the admin rule set"))
        #expect(!AskWordsAsk.matches("how many apps are muted"))
    }
}
