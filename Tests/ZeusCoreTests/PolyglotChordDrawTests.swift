import Testing
@testable import ZeusCore

struct PolyglotChordDrawTests {
    private func cards(_ plan: PolyglotChordDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshKeyUsesTheDefaultEngineChoice() {
        let usual = PolyglotChordDraw.plan(key: "Default", engine: "Start")
        #expect(cards(usual) == ["Chord", "Key: Default", "Hear: Start"])
        #expect(PolyglotChordAsk.line(key: "Default", engine: "Start") == "The Polyglot key is the default, and the engine is chosen at start.")
        #expect(usual.boltCaption(at: 0) == "Chord")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Hear: Start")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(PolyglotChordAsk.line(key: "Off", engine: "Parakeet") == "The Polyglot key is off, and the engine is Parakeet.")
        #expect(PolyglotChordAsk.line(key: "Chosen", engine: "Apple") == "The Polyglot key is one you chose, and the engine is Apple.")
        #expect(cards(PolyglotChordDraw.plan(key: "Right Option", engine: "Start")) == ["Chord", "Can't"])
        #expect(PolyglotChordAsk.line(key: "Default", engine: "Whisper") == "I can't read the Polyglot key.")
    }

    @Test func aLiveTranslationStaysOffThisAsk() {
        #expect(PolyglotChordAsk.matches("what is the polyglot key"))
        #expect(PolyglotChordAsk.matches("Hey Zeus, which engine hears Polyglot?"))
        #expect(PolyglotChordAsk.matches("is the polyglot key off"))
        #expect(!PolyglotChordAsk.matches("how is polyglot set"))
        #expect(!PolyglotChordAsk.matches("how is polyglot"))
        #expect(!PolyglotChordAsk.matches("how is captions set"))
        #expect(!PolyglotChordAsk.matches("how does dictation paste"))
    }
}
