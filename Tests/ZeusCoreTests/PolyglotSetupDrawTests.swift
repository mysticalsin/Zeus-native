import Testing
@testable import ZeusCore

struct PolyglotSetupDrawTests {
    private func cards(_ plan: PolyglotSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func workListenAndLanguageFollowTranslate() {
        let usual = PolyglotSetupDraw.plan(work: "On", listen: "Microphone", into: "English")
        #expect(cards(usual) == ["Translate", "Work: On", "Listen: Microphone", "Into: English"])
        #expect(PolyglotSetupAsk.line(work: "On", listen: "Microphone", into: "English") == "Polyglot is on, listens to Microphone, and translates into English.")
        #expect(usual.boltCaption(at: 0) == "Translate")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Into: English")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        let chinese = PolyglotSetupDraw.plan(work: "Off", listen: "Mac audio", into: "Chinese (Simplified)")
        #expect(cards(chinese) == ["Translate", "Work: Off", "Listen: Mac audio", "Into: Chinese (Simplified)"])
        #expect(PolyglotSetupAsk.line(work: "On", listen: "Both", into: "Portuguese") == "Polyglot is on, listens to Both, and translates into Portuguese.")
        #expect(cards(PolyglotSetupDraw.plan(work: "On", listen: "Headphones", into: "English")) == ["Translate", "Can't"])
        #expect(PolyglotSetupAsk.line(work: "Maybe", listen: "Microphone", into: "Klingon") == "I can't read how Polyglot is set.")
    }

    @Test func theLivePhaseStaysOffThisAsk() {
        #expect(PolyglotSetupAsk.matches("how's polyglot set"))
        #expect(PolyglotSetupAsk.matches("Hey Zeus, which language does polyglot translate to?"))
        #expect(PolyglotSetupAsk.matches("polyglot settings"))
        #expect(!PolyglotSetupAsk.matches("how's polyglot"))
        #expect(!PolyglotSetupAsk.matches("is polyglot on"))
        #expect(!PolyglotSetupAsk.matches("how's the browser agent set"))
        #expect(!PolyglotSetupAsk.matches("start live translation"))
    }
}
