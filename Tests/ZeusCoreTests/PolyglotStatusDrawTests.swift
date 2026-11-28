import Testing
@testable import ZeusCore

struct PolyglotStatusDrawTests {
    private func cards(_ plan: PolyglotStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func listeningDrawsTheLanguageAndLeavesCaptionsOff() {
        let plan = PolyglotStatusDraw.plan(seen: true, phase: "Listening", language: "Portuguese")
        #expect(cards(plan) == ["Polyglot", "Listening", "Portuguese"])
        #expect(PolyglotStatusAsk.line(seen: true, phase: "Listening", language: "Portuguese") == "Polyglot is listening. It translates to Portuguese.")
        #expect(plan.boltCaption(at: 0) == "Polyglot")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Listening")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Portuguese")
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(!cards(plan).joined(separator: " ").contains("swordfish"))
        #expect(cards(PolyglotStatusDraw.plan(seen: false, phase: "Listening", language: "Portuguese")) == ["Polyglot", "Can't"])
        #expect(PolyglotStatusAsk.line(seen: false, phase: "Listening", language: "Portuguese") == "I can't read Polyglot.")
    }

    @Test func readyAndStartingUseThePageWord() {
        #expect(cards(PolyglotStatusDraw.plan(seen: true, phase: "Ready", language: "")) == ["Polyglot", "Ready"])
        #expect(PolyglotStatusAsk.line(seen: true, phase: "Ready", language: " ") == "Polyglot is ready.")
        let starting = PolyglotStatusAsk.starting
        #expect(cards(PolyglotStatusDraw.plan(seen: true, phase: starting, language: "Japanese")) == ["Polyglot", starting, "Japanese"])
        #expect(PolyglotStatusAsk.line(seen: true, phase: starting, language: "Japanese") == "Polyglot is starting. It translates to Japanese.")
        #expect(PolyglotStatusAsk.matches("is translation on"))
        #expect(PolyglotStatusAsk.matches("Hey Zeus, how's polyglot?"))
        #expect(!PolyglotStatusAsk.matches("start live translation"))
        #expect(!PolyglotStatusAsk.matches("is dictation on"))
        #expect(!PolyglotStatusAsk.matches("where is the sound going"))
        #expect(!PolyglotStatusAsk.matches("how's the lid"))
    }
}
