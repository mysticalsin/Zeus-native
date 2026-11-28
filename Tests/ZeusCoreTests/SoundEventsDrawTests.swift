import Testing
@testable import ZeusCore

struct SoundEventsDrawTests {
    private func cards(_ plan: SoundEventsDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func requestsDoneAndTodoFollowEvents() {
        let usual = SoundEventsDraw.plan(requests: "On", done: "On", todo: "On")
        #expect(cards(usual) == ["Events", "Requests: On", "Done: On", "Todo: On"])
        #expect(SoundEventsAsk.line(requests: "On", done: "On", todo: "On") == "Requests are on, completion is on, and a checked to-do is on.")
        #expect(usual.boltCaption(at: 0) == "Events")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Todo: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(SoundEventsAsk.line(requests: "Off", done: "On", todo: "Off") == "Requests are off, completion is on, and a checked to-do is off.")
        #expect(cards(SoundEventsDraw.plan(requests: "Maybe", done: "On", todo: "On")) == ["Events", "Can't"])
        #expect(SoundEventsAsk.line(requests: "On", done: "Loud", todo: "On") == "I can't read which events play a sound.")
    }

    @Test func theCueStylesAndTheVoiceCuesStayOffThisAsk() {
        #expect(SoundEventsAsk.matches("which events play a sound"))
        #expect(SoundEventsAsk.matches("Hey Zeus, does a to-do play a sound?"))
        #expect(SoundEventsAsk.matches("sound event settings"))
        #expect(!SoundEventsAsk.matches("what are the cue sounds"))
        #expect(!SoundEventsAsk.matches("which voice cues"))
        #expect(!SoundEventsAsk.matches("how's captions set"))
        #expect(!SoundEventsAsk.matches("what's the volume"))
    }
}
