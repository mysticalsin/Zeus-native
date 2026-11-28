import Testing
@testable import ZeusCore

struct AnswerPathDrawTests {
    private func cards(_ plan: AnswerPathDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshAnswerIsFilledIn() {
        let usual = AnswerPathDraw.plan(way: "Filled", again: "Off")
        #expect(cards(usual) == ["Back", "Way: Filled", "Again: Off"])
        #expect(AnswerPathAsk.line(way: "Filled", again: "Off") == "Answers are filled into the question, and try again is hidden.")
        #expect(usual.boltCaption(at: 0) == "Back")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Again: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(AnswerPathAsk.line(way: "Message", again: "On") == "Answers are sent as a message, and try again is shown.")
        #expect(cards(AnswerPathDraw.plan(way: "Allow", again: "Off")) == ["Back", "Can't"])
        #expect(AnswerPathAsk.line(way: "Filled", again: "Maybe") == "I can't read how question answers go back.")
    }

    @Test func finishedAgentCardsStayOffThisAsk() {
        #expect(AnswerPathAsk.matches("how do question answers go back"))
        #expect(AnswerPathAsk.matches("Hey Zeus, can I try filling answers again?"))
        #expect(AnswerPathAsk.matches("are answers sent as a message"))
        #expect(!AnswerPathAsk.matches("how are finished agents shown"))
        #expect(!AnswerPathAsk.matches("what does recordly capture"))
        #expect(!AnswerPathAsk.matches("how are routines set"))
        #expect(!AnswerPathAsk.matches("how are approval words set"))
    }
}
