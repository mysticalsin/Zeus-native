import Testing
@testable import ZeusCore

struct TimerFinishedDrawTests {
    @Test func aFinishedTimerShowsTimesUp() throws {
        let plan = try #require(TimerFinishedDraw.from(line: TimerFinishedDraw.line))
        func cards(_ plan: TimerFinishedDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Timer", "Time's up"])
        #expect(plan.boltCaption(at: 0) == "Timer")
        #expect(plan.boltCaption(at: 100) == "Time's up")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func startingAndCancellingAreNotTheFinish() {
        #expect(TimerFinishedDraw.from(line: "") == nil)
        #expect(TimerFinishedDraw.from(line: "Timer cancelled.") == nil)
        #expect(TimerFinishedDraw.from(line: "No timer is running.") == nil)
        #expect(TimerFinishedDraw.from(line: "Timer set for 5 minutes.") == nil)
    }
}
