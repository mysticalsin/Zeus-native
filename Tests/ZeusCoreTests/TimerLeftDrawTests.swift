import Testing
@testable import ZeusCore

struct TimerLeftDrawTests {
    private func cards(_ plan: TimerLeftDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func timeLeftDrawsTheLengthThenTheState() {
        let plan = TimerLeftDraw.plan(seconds: 5 * 60, state: "Running")
        #expect(plan.map(cards) == ["Left", "5 minutes", "Running"])
        #expect(TimerLeftAsk.line(seconds: 5 * 60, state: "Running") == "5 minutes left.")
        #expect(TimerLeftAsk.line(seconds: 90, state: "Paused") == "1 minute 30 seconds left, paused.")
        #expect(TimerLeftAsk.line(seconds: 12 * 60, state: "Focus") == "12 minutes left on focus.")
        #expect(TimerLeftAsk.line(seconds: 5 * 60, state: "Break") == "5 minutes left on the break.")
        #expect(plan?.boltCaption(at: 0) == "Left")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "5 minutes")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Running")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(TimerLeftDraw.plan(seconds: -1, state: "Running") == nil)
        #expect(TimerLeftDraw.plan(seconds: 30, state: " ") == nil)
    }

    @Test func aNewTimerAndACountdownAreNotTimeLeft() {
        #expect(TimerLeftAsk.matches("how much time is left"))
        #expect(TimerLeftAsk.matches("Hey Zeus, how's my timer?"))
        #expect(TimerLeftAsk.matches("time left"))
        #expect(!TimerLeftAsk.matches("set a timer for 5 minutes"))
        #expect(!TimerLeftAsk.matches("how many days left"))
        #expect(!TimerLeftAsk.matches("start focus"))
        #expect(!TimerLeftAsk.matches("what are my agents doing"))
    }
}
