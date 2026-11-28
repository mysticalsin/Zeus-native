import Testing
@testable import ZeusCore

struct ClickMissDrawTests {
    @Test func aMissingNamedClickShowsNothing() throws {
        let plan = try #require(ClickMissDraw.from(line: "Nothing called \"Save\" to click on this page"))
        func cards(_ plan: ClickMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Nothing", "Save"])
        #expect(plan.boltCaption(at: 0) == "Nothing")
        #expect(plan.boltCaption(at: 100) == "Save")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anEmptyNameAndADisabledClickAreNotThisMiss() {
        #expect(ClickMissDraw.from(line: "") == nil)
        #expect(ClickMissDraw.from(line: "Nothing called \"\" to click on this page") == nil)
        #expect(ClickMissDraw.from(line: "Nothing called Save to click on this page") == nil)
        #expect(ClickMissDraw.from(line: "Nothing called \"Save\" to click on this page.") == nil)
        #expect(ClickMissDraw.from(line: "\"Save\" can't be clicked right now.") == nil)
        #expect(ClickMissDraw.from(line: "No text field on this page") == nil)
        #expect(ClickMissDraw.from(line: "Okay, I left it.") == nil)
        #expect(ClickMissDraw.from(line: "There's no element 3 on this page.") == nil)
    }
}
