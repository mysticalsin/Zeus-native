import Testing
@testable import ZeusCore

struct FocusLengthDrawTests {
    private func cards(_ plan: FocusLengthDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshRoundIsTwentyFiveAndFive() {
        let usual = FocusLengthDraw.plan(focus: "25", rest: "5")
        #expect(cards(usual) == ["Round", "Focus: 25", "Break: 5"])
        #expect(FocusLengthAsk.line(focus: "25", rest: "5") == "A focus round is 25 minutes, and the break is 5 minutes.")
        #expect(usual.boltCaption(at: 0) == "Round")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Break: 5")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FocusLengthAsk.line(focus: "1", rest: "1") == "A focus round is 1 minute, and the break is 1 minute.")
        #expect(FocusLengthAsk.line(focus: "50", rest: "10") == "A focus round is 50 minutes, and the break is 10 minutes.")
        #expect(cards(FocusLengthDraw.plan(focus: "0", rest: "5")) == ["Round", "Can't"])
        #expect(FocusLengthAsk.line(focus: "181", rest: "5") == "I can't read the focus lengths.")
    }

    @Test func startingFocusStaysOffThisAsk() {
        #expect(FocusLengthAsk.matches("how long is a focus round"))
        #expect(FocusLengthAsk.matches("Hey Zeus, what is the break length?"))
        #expect(FocusLengthAsk.matches("how is focus set"))
        #expect(!FocusLengthAsk.matches("start focus"))
        #expect(!FocusLengthAsk.matches("rounds today"))
        #expect(!FocusLengthAsk.matches("which models does zeus use"))
        #expect(!FocusLengthAsk.matches("do screen shares show zeus"))
    }
}
