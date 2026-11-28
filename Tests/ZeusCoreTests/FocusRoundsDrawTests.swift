import Testing
@testable import ZeusCore

struct FocusRoundsDrawTests {
    private func cards(_ plan: FocusRoundsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneRoundDrawsTheCountThenToday() {
        let plan = FocusRoundsDraw.plan(count: 1)
        #expect(plan.map(cards) == ["Rounds", "1", "Today"])
        #expect(FocusRoundsAsk.line(count: 1) == "You finished 1 focus round today.")
        #expect(plan?.boltCaption(at: 0) == "Rounds")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "1")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Today")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(FocusRoundsDraw.plan(count: 0) == nil)
        #expect(cards(FocusRoundsDraw.none()) == ["Rounds", "None"])
        #expect(FocusRoundsAsk.none == "No focus rounds today.")
    }

    @Test func severalRoundsStayOffTheFocusCommand() {
        let plan = FocusRoundsDraw.plan(count: 4)
        #expect(plan.map(cards) == ["Rounds", "4", "Today"])
        #expect(FocusRoundsAsk.line(count: 4) == "You finished 4 focus rounds today.")
        #expect(FocusRoundsAsk.matches("how many rounds today"))
        #expect(FocusRoundsAsk.matches("Hey Zeus, how many focus rounds?"))
        #expect(FocusRoundsAsk.matches("rounds today"))
        #expect(!FocusRoundsAsk.matches("start focus"))
        #expect(!FocusRoundsAsk.matches("how much time is left"))
        #expect(!FocusRoundsAsk.matches("how many to-dos"))
        #expect(!FocusRoundsAsk.matches("is caps lock on"))
        #expect(!FocusRoundsAsk.matches("what's in front"))
    }
}
