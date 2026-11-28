import Testing
@testable import ZeusCore

struct FocusSessionDrawTests {
    private func cards(_ plan: FocusSessionDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFocusDrawsTheLengthAndABreakDrawsBreak() {
        let focus = FocusSessionDraw.plan(seconds: 25 * 60, breakTime: false)
        let rest = FocusSessionDraw.plan(seconds: 5 * 60, breakTime: true)
        #expect(focus.map(cards) == ["Focus", "25 minutes"])
        #expect(rest.map(cards) == ["Break", "5 minutes"])
        #expect(FocusSessionAsk.lengthLine(seconds: 25 * 60, breakTime: false) == "Focus for 25 minutes.")
        #expect(FocusSessionAsk.lengthLine(seconds: 5 * 60, breakTime: true) == "Break for 5 minutes.")
        #expect(focus?.boltCaption(at: 0) == "Focus")
        #expect(focus?.boltCaption(at: ExplainBeatSchedule.gap) == "25 minutes")
        #expect(focus?.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(focus?.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(FocusSessionDraw.plan(seconds: -1, breakTime: false) == nil)
    }

    @Test func pauseStopAndReadyNameTheSession() {
        #expect(cards(FocusSessionDraw.paused()) == ["Focus", "Paused"])
        #expect(cards(FocusSessionDraw.stopped(breakTime: false)) == ["Focus", "Stopped"])
        #expect(cards(FocusSessionDraw.stopped(breakTime: true)) == ["Break", "Stopped"])
        #expect(cards(FocusSessionDraw.ready()) == ["Focus", "Ready"])
        #expect(FocusSessionAsk.paused == "Focus paused.")
        #expect(FocusSessionAsk.focusStopped == "Focus stopped.")
        #expect(FocusSessionAsk.breakStopped == "Break stopped.")
        #expect(FocusSessionAsk.notRunning == "Focus isn't running.")
    }

    @Test func aFinishedRoundDrawsDoneAndATimerAskIsNotFocus() {
        let done = FocusSessionDraw.focusDone()
        #expect(cards(done) == ["Focus", "Done", "Break"])
        #expect(done.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Break")
        #expect(done.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(cards(FocusSessionDraw.breakOver()) == ["Break", "Done"])
        #expect(FocusSessionAsk.focusDone == "Focus done. Take a break.")
        #expect(FocusSessionAsk.breakOver == "Break over. Back to it.")
        #expect(FocusSessionAsk.command(in: "start focus") == .start(nil))
        #expect(FocusSessionAsk.command(in: "Hey Zeus, focus for 25 minutes") == .start(25 * 60))
        #expect(FocusSessionAsk.command(in: "start a 25 minute focus") == .start(25 * 60))
        #expect(FocusSessionAsk.command(in: "pause the focus") == .pause)
        #expect(FocusSessionAsk.command(in: "stop the timer") == nil)
        #expect(FocusSessionAsk.command(in: "what's playing") == nil)
        #expect(FocusSessionAsk.command(in: "set a timer for 5 minutes") == nil)
    }
}
