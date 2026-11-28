import Testing
@testable import ZeusCore

struct NotFieldDrawTests {
    @Test func anElementThatIsNotATextFieldShowsItsNumber() throws {
        let plan = try #require(NotFieldDraw.from(line: "Element 3 isn't a text field."))
        func cards(_ plan: NotFieldDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Field", "3"])
        #expect(plan.boltCaption(at: 0) == "Field")
        #expect(plan.boltCaption(at: 100) == "3")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aMissingFieldAndAMissingChoiceAreNotThisElement() {
        #expect(NotFieldDraw.from(line: "") == nil)
        #expect(NotFieldDraw.from(line: "Element isn't a text field.") == nil)
        #expect(NotFieldDraw.from(line: "Element 3 isn't a text field") == nil)
        #expect(NotFieldDraw.from(line: "Element Save isn't a text field.") == nil)
        #expect(NotFieldDraw.from(line: "No text field on this page") == nil)
        #expect(NotFieldDraw.from(line: "No field called \"Search\"") == nil)
        #expect(NotFieldDraw.from(line: "There's no element 3 on this page.") == nil)
        #expect(NotFieldDraw.from(line: "\"Red\" isn't one of the choices.") == nil)
    }
}
