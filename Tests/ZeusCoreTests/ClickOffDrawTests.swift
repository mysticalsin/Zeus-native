import Testing
@testable import ZeusCore

struct ClickOffDrawTests {
    @Test func aControlZeusCouldNotClickShowsItsName() throws {
        let plan = try #require(ClickOffDraw.from(line: "\"Save\" can't be clicked right now."))
        func cards(_ plan: ClickOffDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Click", "Save"])
        #expect(plan.boltCaption(at: 0) == "Click")
        #expect(plan.boltCaption(at: 100) == "Save")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func anEmptyNameAndAMissingFieldAreNotThisClick() {
        #expect(ClickOffDraw.from(line: "") == nil)
        #expect(ClickOffDraw.from(line: "\"\" can't be clicked right now.") == nil)
        #expect(ClickOffDraw.from(line: "Save can't be clicked right now.") == nil)
        #expect(ClickOffDraw.from(line: "\"Save\" isn't one of the choices.") == nil)
        #expect(ClickOffDraw.from(line: "No text field on this page") == nil)
        #expect(ClickOffDraw.from(line: "Read page.target before approving this action. Nothing was changed.") == nil)
        #expect(ClickOffDraw.from(line: "Okay, I left it.") == nil)
    }
}
