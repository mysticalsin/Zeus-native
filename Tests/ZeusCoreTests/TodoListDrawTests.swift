import Testing
@testable import ZeusCore

struct TodoListDrawTests {
    @Test func eachAddedTitleIsDrawnInOrder() throws {
        let plan = try #require(TodoListDraw.plan(titles: ["Call Ana", "  ", "Send the invoice", "Book the dentist", "Extra"]))
        #expect(plan.titles == ["Call Ana", "Send the invoice", "Book the dentist"])
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["To-dos", "Call Ana", "Send the invoice", "Book the dentist"])
        #expect(plan.boltCaption(at: 0) == "To-dos")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Call Ana")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Send the invoice")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankListIsNotDrawn() {
        #expect(TodoListDraw.plan(titles: []) == nil)
        #expect(TodoListDraw.plan(titles: ["  ", "\n"]) == nil)
    }

    @Test func aLongTitleKeepsAShortBolt() throws {
        let title = "Supercalifragilisticexpialidocious reminder for the whole afternoon"
        let plan = try #require(TodoListDraw.plan(titles: [title]))
        #expect(plan.titles[0].hasPrefix("Supercalifragilisticexpialidocious"))
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap).count <= 40)
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) != "To-dos")
    }
}
