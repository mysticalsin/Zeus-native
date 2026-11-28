import Testing
@testable import ZeusCore

struct DictationSetupDrawTests {
    private func cards(_ plan: DictationSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theLanguageKeyAndEngineFollowDictation() {
        let setup = DictationSetupDraw.plan(language: "Automatic", key: "Hold to speak", engine: "Parakeet v3")
        #expect(cards(setup) == ["Dictation", "Language: Automatic", "Key: Hold to speak", "Engine: Parakeet v3"])
        #expect(DictationSetupAsk.line(language: "Automatic", key: "Hold to speak", engine: "Parakeet v3") == "Dictation uses Automatic, Hold to speak, and Parakeet v3.")
        #expect(setup.boltCaption(at: 0) == "Dictation")
        #expect(setup.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Engine: Parakeet v3")
        #expect(setup.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(DictationSetupAsk.line(language: "Portuguese (Brazil)", key: "Press to start and stop", engine: "Apple on-device") == "Dictation uses Portuguese (Brazil), Press to start and stop, and Apple on-device.")
        #expect(cards(DictationSetupDraw.plan(language: "Klingon", key: "Hold to speak", engine: "Parakeet v3")) == ["Dictation", "Can't"])
        #expect(DictationSetupAsk.line(language: "", key: "Hold to speak", engine: "Parakeet v3") == "I can't read how dictation is set.")
    }

    @Test func theLivePhaseAndTheWordCountStayOffThisAsk() {
        #expect(DictationSetupAsk.matches("how's dictation set"))
        #expect(DictationSetupAsk.matches("Hey Zeus, what's the dictation language?"))
        #expect(DictationSetupAsk.matches("dictation language"))
        #expect(!DictationSetupAsk.matches("is dictation on"))
        #expect(!DictationSetupAsk.matches("how's dictation"))
        #expect(!DictationSetupAsk.matches("how many words today"))
        #expect(!DictationSetupAsk.matches("what are the cue sounds"))
    }
}
