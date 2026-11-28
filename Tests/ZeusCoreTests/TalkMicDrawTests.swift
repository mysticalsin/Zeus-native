import Testing
@testable import ZeusCore

struct TalkMicDrawTests {
    private func cards(_ plan: TalkMicDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theChoiceFollowsListen() {
        let usual = TalkMicDraw.plan(hear: "Automatic")
        #expect(cards(usual) == ["Listen", "Mic: Automatic"])
        #expect(TalkMicAsk.line(hear: "Automatic") == "Talk listens on the automatic microphone.")
        #expect(usual.boltCaption(at: 0) == "Listen")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Mic: Automatic")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(TalkMicAsk.line(hear: TalkMicAsk.mac) == "Talk listens on this Mac's microphone.")
        #expect(TalkMicAsk.line(hear: "Chosen") == "Talk listens on a microphone you chose.")
        #expect(TalkMicAsk.line(hear: "Unavailable") == "The talk microphone you chose is unavailable.")
        #expect(cards(TalkMicDraw.plan(hear: "Chosen")) == ["Listen", "Mic: Chosen"])
        #expect(cards(TalkMicDraw.plan(hear: "Headset")) == ["Listen", "Can't"])
        #expect(TalkMicAsk.line(hear: "Bluetooth") == "I can't read the talk microphone.")
    }

    @Test func heyZeusStaysOffThisAsk() {
        #expect(TalkMicAsk.matches("which talk microphone"))
        #expect(TalkMicAsk.matches("Hey Zeus, where is talk listening?"))
        #expect(TalkMicAsk.matches("talk microphone settings"))
        #expect(!TalkMicAsk.matches("is hey zeus on"))
        #expect(!TalkMicAsk.matches("how's dictation set"))
        #expect(!TalkMicAsk.matches("what's the halo entrance"))
        #expect(!TalkMicAsk.matches("how's flick set"))
    }
}
