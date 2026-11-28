import Testing
@testable import ZeusCore

struct DictateHearDrawTests {
    private func cards(_ plan: DictateHearDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesTheSystemDefault() {
        let usual = DictateHearDraw.plan(input: "System default", cue: "70")
        #expect(cards(usual) == ["Input", "Input: System default", "Cue: 70%"])
        #expect(DictateHearAsk.line(input: "System default", cue: "70") == "Dictation uses the system default microphone, and the cue is 70 percent.")
        #expect(usual.boltCaption(at: 0) == "Input")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Cue: 70%")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(DictateHearAsk.line(input: "Chosen", cue: "0") == "Dictation uses a microphone you chose, and the cue is 0 percent.")
        #expect(DictateHearAsk.line(input: "Unavailable", cue: "100") == "The dictation microphone you chose is unavailable, and the cue is 100 percent.")
        #expect(cards(DictateHearDraw.plan(input: "Built-in", cue: "70")) == ["Input", "Can't"])
        #expect(DictateHearAsk.line(input: "System default", cue: "070") == "I can't read the dictation microphone.")
    }

    @Test func theTalkMicrophoneStaysOffThisAsk() {
        #expect(DictateHearAsk.matches("which dictation microphone"))
        #expect(DictateHearAsk.matches("Hey Zeus, how loud is the dictation cue?"))
        #expect(DictateHearAsk.matches("dictation microphone settings"))
        #expect(!DictateHearAsk.matches("which talk microphone"))
        #expect(!DictateHearAsk.matches("what is the dictation sound"))
        #expect(!DictateHearAsk.matches("how is the voice tuned"))
        #expect(!DictateHearAsk.matches("how are updates set"))
    }
}
