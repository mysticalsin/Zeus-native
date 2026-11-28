import Testing
@testable import ZeusCore

struct ChoiceMissDrawTests {
    @Test func aMissingChoiceShowsItsName() throws {
        let plan = try #require(ChoiceMissDraw.from(line: "\"Red\" isn't one of the choices."))
        func cards(_ plan: ChoiceMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Choice", "Red"])
        #expect(plan.boltCaption(at: 0) == "Choice")
        #expect(plan.boltCaption(at: 100) == "Red")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anEmptyChoiceAndAMissingElementAreNotThisChoice() {
        #expect(ChoiceMissDraw.from(line: "") == nil)
        #expect(ChoiceMissDraw.from(line: "\"\" isn't one of the choices.") == nil)
        #expect(ChoiceMissDraw.from(line: "Red isn't one of the choices.") == nil)
        #expect(ChoiceMissDraw.from(line: "\"Red\" isn't one of the choices") == nil)
        #expect(ChoiceMissDraw.from(line: "There's no element 3 on this page.") == nil)
        #expect(ChoiceMissDraw.from(line: "Nothing called \"Save\" to click on this page") == nil)
        #expect(ChoiceMissDraw.from(line: "Element 3 isn't a text field.") == nil)
        #expect(ChoiceMissDraw.from(line: "No text field on this page") == nil)
    }
}
