import Testing
@testable import ZeusCore

struct FocusClockDrawTests {
    private func cards(_ plan: FocusClockDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theClockAndTheRound() {
        let usual = FocusClockDraw.plan(clock: "Idle", kind: "None")
        #expect(cards(usual) == ["Clock", "Run: Idle", "Kind: None"])
        #expect(FocusClockAsk.line(clock: "Idle", kind: "None") == "Focus is idle, and no round is on.")
        #expect(usual.boltCaption(at: 0) == "Clock")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Kind: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FocusClockAsk.line(clock: "Running", kind: "Focus") == "Focus is running, and this round is focus.")
        #expect(FocusClockAsk.line(clock: "Paused", kind: "Break") == "Focus is paused, and this round is a break.")
        #expect(FocusClockAsk.line(clock: "Running", kind: "Timer") == "Focus is running, and this round is a timer.")
        #expect(cards(FocusClockDraw.plan(clock: "Idle", kind: "Focus")) == ["Clock", "Can't"])
        #expect(FocusClockAsk.line(clock: "Running", kind: "None") == "I can't read the focus clock.")
    }

    @Test func startingFocusStaysOffThisAsk() {
        #expect(FocusClockAsk.matches("is focus running"))
        #expect(FocusClockAsk.matches("Hey Zeus, is focus paused?"))
        #expect(FocusClockAsk.matches("is a plain timer running"))
        #expect(!FocusClockAsk.matches("start focus"))
        #expect(!FocusClockAsk.matches("how long is a focus round"))
        #expect(!FocusClockAsk.matches("how many focus rounds"))
        #expect(!FocusClockAsk.matches("are done to-dos shown"))
    }
}
