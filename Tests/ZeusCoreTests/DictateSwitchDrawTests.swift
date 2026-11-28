import Testing
@testable import ZeusCore

struct DictateSwitchDrawTests {
    private func cards(_ plan: DictateSwitchDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallDictatesWithSoundsAndAppleCommands() {
        let usual = DictateSwitchDraw.plan(enabled: "On", sounds: "On", voice: "Off")
        #expect(cards(usual) == ["Dictate", "Dictate: On", "Sounds: On", "Voice: Off"])
        #expect(DictateSwitchAsk.line(enabled: "On", sounds: "On", voice: "Off") == "Dictation is on, its sounds are on, and voice commands stay with Apple.")
        #expect(usual.boltCaption(at: 0) == "Dictate")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Voice: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(DictateSwitchAsk.line(enabled: "Off", sounds: "Off", voice: "On") == "Dictation is off, its sounds are off, and voice commands use the dictation engine.")
        #expect(cards(DictateSwitchDraw.plan(enabled: "Off", sounds: "On", voice: "Off")) == ["Dictate", "Dictate: Off", "Sounds: On", "Voice: Off"])
        #expect(cards(DictateSwitchDraw.plan(enabled: "Maybe", sounds: "On", voice: "Off")) == ["Dictate", "Can't"])
        #expect(DictateSwitchAsk.line(enabled: "On", sounds: "Loud", voice: "Off") == "I can't read whether dictation is enabled.")
    }

    @Test func aLiveDictationStaysOffThisAsk() {
        #expect(DictateSwitchAsk.matches("is dictation enabled"))
        #expect(DictateSwitchAsk.matches("Hey Zeus, does dictation play sounds?"))
        #expect(DictateSwitchAsk.matches("do voice commands use the dictation engine"))
        #expect(!DictateSwitchAsk.matches("is dictation on"))
        #expect(!DictateSwitchAsk.matches("how is dictation set"))
        #expect(!DictateSwitchAsk.matches("what is the dictation sound"))
        #expect(!DictateSwitchAsk.matches("how is sound feedback set"))
    }
}
