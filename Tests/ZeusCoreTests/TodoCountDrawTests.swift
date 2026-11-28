import Testing
@testable import ZeusCore

struct TodoCountDrawTests {
    private func cards(_ plan: TodoCountDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func openToDosDrawTheCountThenWhatIsLate() {
        let plan = TodoCountDraw.plan(open: 3, overdue: 2)
        #expect(plan.map(cards) == ["To-dos", "3", "2 overdue"])
        #expect(TodoCountAsk.line(open: 3, overdue: 2) == "You have 3 to-dos left, 2 overdue.")
        #expect(TodoCountAsk.line(open: 1, overdue: 0) == "You have 1 to-do left.")
        #expect(TodoCountDraw.plan(open: 4, overdue: 0).map(cards) == ["To-dos", "4", "Open"])
        #expect(plan?.boltCaption(at: 0) == "To-dos")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "3")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "2 overdue")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(TodoCountDraw.plan(open: 0, overdue: 0) == nil)
        #expect(TodoCountDraw.plan(open: 1, overdue: 2) == nil)
    }

    @Test func anEmptyListDrawsNoneAndAddingIsNotThisAsk() {
        #expect(cards(TodoCountDraw.none()) == ["To-dos", "None"])
        #expect(cards(TodoCountDraw.clear()) == ["To-dos", "Done"])
        #expect(TodoCountAsk.none == "You have no to-dos.")
        #expect(TodoCountAsk.done == "All to-dos are done.")
        #expect(TodoCountAsk.matches("how many to-dos"))
        #expect(TodoCountAsk.matches("Hey Zeus, how many to-dos left?"))
        #expect(TodoCountAsk.matches("how many tasks do I have"))
        #expect(!TodoCountAsk.matches("add a to-do: buy milk"))
        #expect(!TodoCountAsk.matches("what do I have today"))
        #expect(!TodoCountAsk.matches("how many notifications"))
        #expect(!TodoCountAsk.matches("how many days left"))
    }
}
