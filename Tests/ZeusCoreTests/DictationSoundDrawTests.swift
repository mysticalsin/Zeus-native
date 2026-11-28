import Testing
@testable import ZeusCore

struct DictationSoundDrawTests {
    private func cards(_ plan: DictationSoundDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theStyleFollowsMark() {
        let usual = DictationSoundDraw.plan(style: "Crystal")
        #expect(cards(usual) == ["Mark", "Sound: Crystal"])
        #expect(DictationSoundAsk.line(style: "Crystal") == "Dictation starts and stops with Crystal.")
        #expect(usual.boltCaption(at: 0) == "Mark")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Sound: Crystal")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(DictationSoundAsk.line(style: "None") == "Dictation starts and stops in silence.")
        #expect(DictationSoundAsk.line(style: "Soft click") == "Dictation starts and stops with Soft click.")
        #expect(cards(DictationSoundDraw.plan(style: "Airy")) == ["Mark", "Sound: Airy"])
        #expect(cards(DictationSoundDraw.plan(style: "Beep")) == ["Mark", "Can't"])
        #expect(DictationSoundAsk.line(style: "Chime") == "I can't read the dictation sound.")
    }

    @Test func agentCuesStayOffThisAsk() {
        #expect(DictationSoundAsk.matches("what's the dictation sound"))
        #expect(DictationSoundAsk.matches("Hey Zeus, what sound does dictation make?"))
        #expect(DictationSoundAsk.matches("dictation sound settings"))
        #expect(!DictationSoundAsk.matches("which cue sounds"))
        #expect(!DictationSoundAsk.matches("which extra sounds"))
        #expect(!DictationSoundAsk.matches("how's dictation set"))
        #expect(!DictationSoundAsk.matches("what's the home backdrop"))
    }
}
