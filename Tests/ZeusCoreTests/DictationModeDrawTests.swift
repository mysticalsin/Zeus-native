import Testing
@testable import ZeusCore

struct DictationModeDrawTests {
    private func cards(_ plan: DictationModeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theModeAndTheAppSwitchFollowMode() {
        let usual = DictationModeDraw.plan(mode: "Voice", apps: "Off")
        #expect(cards(usual) == ["Mode", "Using: Voice", "Apps: Off"])
        #expect(DictationModeAsk.line(mode: "Voice", apps: "Off") == "Dictation writes with Voice, and switch by app is off.")
        #expect(usual.boltCaption(at: 0) == "Mode")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Apps: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(DictationModeAsk.line(mode: "Agent prompt", apps: "On") == "Dictation writes with Agent prompt, and switch by app is on.")
        #expect(cards(DictationModeDraw.plan(mode: "Email", apps: "On")) == ["Mode", "Using: Email", "Apps: On"])
        #expect(cards(DictationModeDraw.plan(mode: "Custom", apps: "Off")) == ["Mode", "Can't"])
        #expect(DictationModeAsk.line(mode: "Voice", apps: "Maybe") == "I can't read the dictation mode.")
    }

    @Test func theLanguageAndTheLivePhaseStayOffThisAsk() {
        #expect(DictationModeAsk.matches("which dictation mode"))
        #expect(DictationModeAsk.matches("Hey Zeus, does dictation switch by app?"))
        #expect(DictationModeAsk.matches("dictation mode settings"))
        #expect(!DictationModeAsk.matches("how's dictation set"))
        #expect(!DictationModeAsk.matches("is dictation on"))
        #expect(!DictationModeAsk.matches("how's insomnia set"))
        #expect(!DictationModeAsk.matches("how many words today"))
    }
}
