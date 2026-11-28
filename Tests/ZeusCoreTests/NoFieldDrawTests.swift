import Testing
@testable import ZeusCore

struct NoFieldDrawTests {
    @Test func aPageWithNoTextFieldShowsNone() throws {
        let plan = try #require(NoFieldDraw.from(line: "No text field on this page"))
        func cards(_ plan: NoFieldDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Field", "None"])
        #expect(plan.boltCaption(at: 0) == "Field")
        #expect(plan.boltCaption(at: 100) == "None")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aNamedFieldAndAMissingTargetAreNotThisPage() {
        #expect(NoFieldDraw.from(line: "") == nil)
        #expect(NoFieldDraw.from(line: "No text field on this page.") == nil)
        #expect(NoFieldDraw.from(line: "No field called \"Search\"") == nil)
        #expect(NoFieldDraw.from(line: "Okay, I didn't type anything.") == nil)
        #expect(NoFieldDraw.from(line: "Read page.target before approving this action. Nothing was changed.") == nil)
        #expect(NoFieldDraw.from(line: "No active Chrome tab") == nil)
        #expect(NoFieldDraw.from(line: "The approved document is no longer available. Nothing was changed.") == nil)
    }
}
