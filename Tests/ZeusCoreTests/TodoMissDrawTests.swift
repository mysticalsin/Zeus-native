import Testing
@testable import ZeusCore

struct TodoMissDrawTests {
    @Test func aToDoThatWasNotAddedShowsNotAdded() throws {
        let plan = try #require(TodoMissDraw.from(line: TodoMissDraw.line))
        func cards(_ plan: TodoMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["To-do", "Not added"])
        #expect(plan.boltCaption(at: 0) == "To-do")
        #expect(plan.boltCaption(at: 100) == "Not added")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anAddedToDoAndOtherLinesAreNotThisCard() {
        #expect(TodoMissDraw.from(line: "") == nil)
        #expect(TodoMissDraw.from(line: "Added milk.") == nil)
        #expect(TodoMissDraw.from(line: "Done: milk.") == nil)
        #expect(TodoMissDraw.from(line: "I couldn't find a to-do called milk.") == nil)
        #expect(TodoMissDraw.from(line: "rm is blocked") == nil)
    }
}
