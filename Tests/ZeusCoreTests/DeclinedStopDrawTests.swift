import Testing
@testable import ZeusCore

struct DeclinedStopDrawTests {
    @Test func aDeclinedStepShowsTheAction() throws {
        let plan = try #require(DeclinedStopDraw.from(line: "Okay, I didn't click submit. I've stopped there."))
        func cards(_ plan: DeclinedStopDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Stopped", "click submit"])
        #expect(plan.boltCaption(at: 0) == "Stopped")
        #expect(plan.boltCaption(at: 100) == "click submit")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankActionAndOtherStopsAreNotDeclined() {
        #expect(DeclinedStopDraw.from(line: "") == nil)
        #expect(DeclinedStopDraw.from(line: "Okay, I didn't . I've stopped there.") == nil)
        #expect(DeclinedStopDraw.from(line: "Okay, I didn't type anything.") == nil)
        #expect(DeclinedStopDraw.from(line: "Okay, I left it open.") == nil)
        #expect(DeclinedStopDraw.from(line: "you stopped it before it began.") == nil)
        #expect(DeclinedStopDraw.from(line: "the browser agent is off. Turn it on in Settings.") == nil)
    }
}
