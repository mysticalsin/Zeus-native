import Testing
@testable import ZeusCore

struct KokoroSetupDrawTests {
    private func cards(_ plan: KokoroSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallIsNotSetUpOnMichael() {
        let usual = KokoroSetupDraw.plan(setup: "Not set up", voice: "Michael (US)")
        #expect(cards(usual) == ["Kokoro", "Setup: Not set up", "Voice: Michael (US)"])
        #expect(KokoroSetupAsk.line(setup: "Not set up", voice: "Michael (US)") == "Kokoro is not set up, and the voice is Michael (US).")
        #expect(usual.boltCaption(at: 0) == "Kokoro")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Voice: Michael (US)")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(KokoroSetupAsk.line(setup: "Ready", voice: "Emma (UK)") == "Kokoro is ready, and the voice is Emma (UK).")
        #expect(KokoroSetupAsk.line(setup: "Ready", voice: "Bella (US)") == "Kokoro is ready, and the voice is Bella (US).")
        #expect(cards(KokoroSetupDraw.plan(setup: "Missing", voice: "Michael (US)")) == ["Kokoro", "Can't"])
        #expect(KokoroSetupAsk.line(setup: "Ready", voice: "Alex") == "I can't read how Kokoro is set.")
    }

    @Test func theChosenEngineStaysOffThisAsk() {
        #expect(KokoroSetupAsk.matches("which kokoro voice"))
        #expect(KokoroSetupAsk.matches("Hey Zeus, is kokoro ready?"))
        #expect(KokoroSetupAsk.matches("is kokoro set up"))
        #expect(!KokoroSetupAsk.matches("which voice"))
        #expect(!KokoroSetupAsk.matches("how is the voice tuned"))
        #expect(!KokoroSetupAsk.matches("which chat model"))
        #expect(!KokoroSetupAsk.matches("how is any llm set"))
    }
}
