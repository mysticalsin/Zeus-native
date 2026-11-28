import Testing
@testable import ZeusCore

struct DictationRecordDrawTests {
    private func cards(_ plan: DictationRecordDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theFourSwitchesFollowRecord() {
        let usual = DictationRecordDraw.plan(pill: "On", check: "Off", music: "On", type: "Off")
        #expect(cards(usual) == ["Record", "Pill: On", "Check: Off", "Music: On", "Type: Off"])
        #expect(DictationRecordAsk.line(pill: "On", check: "Off", music: "On", type: "Off") == "The recorder is on, check before writing is off, pause music is on, and type instead of paste is off.")
        #expect(usual.boltCaption(at: 0) == "Record")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Type: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(DictationRecordAsk.line(pill: "Off", check: "On", music: "Off", type: "On") == "The recorder is off, check before writing is on, pause music is off, and type instead of paste is on.")
        #expect(cards(DictationRecordDraw.plan(pill: "Maybe", check: "Off", music: "On", type: "Off")) == ["Record", "Can't"])
        #expect(DictationRecordAsk.line(pill: "On", check: "Off", music: "Loud", type: "Off") == "I can't read how recording is set.")
    }

    @Test func aLiveRecordingAndTheWritingModeStayOffThisAsk() {
        #expect(DictationRecordAsk.matches("how's recording set"))
        #expect(DictationRecordAsk.matches("Hey Zeus, does dictation pause music?"))
        #expect(DictationRecordAsk.matches("recording settings"))
        #expect(!DictationRecordAsk.matches("are you recording"))
        #expect(!DictationRecordAsk.matches("which dictation mode"))
        #expect(!DictationRecordAsk.matches("how's the voice glow set"))
        #expect(!DictationRecordAsk.matches("is dictation on"))
    }
}
