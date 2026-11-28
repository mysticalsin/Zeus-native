import Testing
@testable import ZeusCore

struct NoTimerDrawTests {
    @Test func noTimerRunningShowsNone() throws {
        let plan = try #require(NoTimerDraw.from(line: "No timer is running."))
        func cards(_ plan: NoTimerDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Timer", "None"])
        #expect(plan.boltCaption(at: 0) == "Timer")
        #expect(plan.boltCaption(at: 100) == "None")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aFinishedTimerAndANamedFieldAreNotThisNotice() {
        #expect(NoTimerDraw.from(line: "") == nil)
        #expect(NoTimerDraw.from(line: "No timer is running") == nil)
        #expect(NoTimerDraw.from(line: "Time's up.") == nil)
        #expect(NoTimerDraw.from(line: "No field called \"Search\"") == nil)
        #expect(NoTimerDraw.from(line: "No text field on this page") == nil)
        #expect(NoTimerDraw.from(line: "Missing text") == nil)
    }
}
