import Testing
@testable import ZeusCore

struct LanguagePackDrawTests {
    private func cards(_ plan: LanguagePackDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func fourPacksFollowPacks() {
        let usual = LanguagePackDraw.plan(english: "Installed", french: "Missing", spanish: "Queued", portuguese: "Failed")
        #expect(cards(usual) == ["Packs", "English: Installed", "French: Missing", "Spanish: Queued", "Portuguese: Failed"])
        #expect(LanguagePackAsk.line(english: "Installed", french: "Missing", spanish: "Queued", portuguese: "Failed") == "English is installed, French is not installed, Spanish is queued, and Portuguese failed.")
        #expect(usual.boltCaption(at: 0) == "Packs")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Portuguese: Failed")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(LanguagePackAsk.line(english: "Installing", french: "Waiting", spanish: "Unavailable", portuguese: "Installed") == "English is installing, French is waiting, Spanish is not available, and Portuguese is installed.")
        #expect(cards(LanguagePackDraw.plan(english: "Installed", french: "Installed", spanish: "Installed", portuguese: "Installed")) == ["Packs", "English: Installed", "French: Installed", "Spanish: Installed", "Portuguese: Installed"])
        #expect(cards(LanguagePackDraw.plan(english: "Ready", french: "Missing", spanish: "Queued", portuguese: "Failed")) == ["Packs", "Can't"])
        #expect(LanguagePackAsk.line(english: "Installed", french: "Gone", spanish: "Queued", portuguese: "Failed") == "I can't read the language packs.")
    }

    @Test func theDictationLanguageStaysOffThisAsk() {
        #expect(LanguagePackAsk.matches("which language packs"))
        #expect(LanguagePackAsk.matches("Hey Zeus, how are the language packs?"))
        #expect(LanguagePackAsk.matches("language pack settings"))
        #expect(!LanguagePackAsk.matches("which dictation language"))
        #expect(!LanguagePackAsk.matches("how's dictation set"))
        #expect(!LanguagePackAsk.matches("how's scribe set"))
        #expect(!LanguagePackAsk.matches("how's research set"))
    }
}
