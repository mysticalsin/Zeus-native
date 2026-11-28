import Testing
@testable import ZeusCore

struct ElementMissDrawTests {
    @Test func aMissingNumberedElementShowsItsNumber() throws {
        let plan = try #require(ElementMissDraw.from(line: "There's no element 3 on this page."))
        func cards(_ plan: ElementMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Element", "3"])
        #expect(plan.boltCaption(at: 0) == "Element")
        #expect(plan.boltCaption(at: 100) == "3")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aNamedClickAndABlankNumberAreNotThisElement() {
        #expect(ElementMissDraw.from(line: "") == nil)
        #expect(ElementMissDraw.from(line: "There's no element on this page.") == nil)
        #expect(ElementMissDraw.from(line: "There's no element 3 on this page") == nil)
        #expect(ElementMissDraw.from(line: "There's no element Save on this page.") == nil)
        #expect(ElementMissDraw.from(line: "Nothing called \"Save\" to click on this page") == nil)
        #expect(ElementMissDraw.from(line: "\"Save\" can't be clicked right now.") == nil)
        #expect(ElementMissDraw.from(line: "Element 3 isn't a text field.") == nil)
        #expect(ElementMissDraw.from(line: "No text field on this page") == nil)
    }
}
