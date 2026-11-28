import Testing
@testable import ZeusCore

struct RecordingStatusDrawTests {
    private func cards(_ plan: RecordingStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func scribeDrawsTheNameThenTheClock() {
        let plan = RecordingStatusDraw.plan(who: .any, scribe: true, recordly: false, seconds: 64)
        #expect(cards(plan) == ["Recording", "Scribe", "1:04"])
        #expect(RecordingAsk.line(who: .any, scribe: true, recordly: false, seconds: 64) == "Scribe is recording. 1:04.")
        #expect(plan.boltCaption(at: 0) == "Recording")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Scribe")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "1:04")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(RecordingAsk.clock(3661) == "1:01:01")
        #expect(RecordingAsk.clock(-3) == "0:00")
    }

    @Test func offAndBothStayOffTheWordCount() {
        let off = RecordingStatusDraw.plan(who: .any, scribe: false, recordly: false, seconds: 10)
        #expect(cards(off) == ["Recording", "Off"])
        #expect(RecordingAsk.line(who: .any, scribe: false, recordly: false, seconds: 10) == "Nothing is recording.")
        #expect(off.boltCaption(at: ExplainBeatSchedule.gap) == "Off")
        let both = RecordingStatusDraw.plan(who: .any, scribe: true, recordly: true, seconds: 5)
        #expect(cards(both) == ["Recording", "Both"])
        #expect(RecordingAsk.line(who: .any, scribe: true, recordly: true, seconds: 5) == "Scribe and Recordly are recording.")
        let named = RecordingStatusDraw.plan(who: .scribe, scribe: false, recordly: true, seconds: 9)
        #expect(cards(named) == ["Recording", "Off"])
        #expect(RecordingAsk.line(who: .scribe, scribe: false, recordly: true, seconds: 9) == "Scribe isn't recording.")
        #expect(RecordingAsk.who(in: "are you recording") == .any)
        #expect(RecordingAsk.who(in: "Hey Zeus, is scribe recording?") == .scribe)
        #expect(RecordingAsk.who(in: "is recordly recording") == .recordly)
        #expect(RecordingAsk.who(in: "how many words today") == nil)
        #expect(RecordingAsk.who(in: "what's playing") == nil)
        #expect(RecordingAsk.who(in: "start recording") == nil)
        #expect(RecordingAsk.who(in: "how many rounds today") == nil)
    }
}
