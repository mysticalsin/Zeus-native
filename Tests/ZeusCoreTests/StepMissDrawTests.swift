import Testing
@testable import ZeusCore

struct StepMissDrawTests {
    @Test func aBrowserStepThatWillNotReadShowsNoStep() throws {
        let plan = try #require(StepMissDraw.from(line: StepMissDraw.line))
        func cards(_ plan: StepMissDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Browser", "No step"])
        #expect(plan.boltCaption(at: 0) == "Browser")
        #expect(plan.boltCaption(at: 100) == "No step")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aRealStepAndOtherLinesAreNotThisCard() {
        #expect(StepMissDraw.from(line: "") == nil)
        #expect(StepMissDraw.from(line: "Clicking the File menu") == nil)
        #expect(StepMissDraw.from(line: "That link isn't a web page, so I left it.") == nil)
        #expect(StepMissDraw.from(line: "Okay, I left it.") == nil)
        #expect(StepMissDraw.from(line: "I couldn't tell what to run, so I left it.") == nil)
    }
}
