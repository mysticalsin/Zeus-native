import Testing
@testable import ZeusCore

struct ExplainSetupDrawTests {
    private func cards(_ plan: ExplainSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func keyAndLocalFollowExplain() {
        let usual = ExplainSetupDraw.plan(key: "Command-Shift-Space", local: "Off")
        #expect(cards(usual) == ["Explain", "Key: Command-Shift-Space", "Local: Off"])
        #expect(ExplainSetupAsk.line(key: "Command-Shift-Space", local: "Off") == "Spoken requests use Command, Shift, and Space, and model requests may leave this Mac.")
        #expect(usual.boltCaption(at: 0) == "Explain")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Local: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ExplainSetupAsk.line(key: "Command-Shift-V", local: "On") == "Spoken requests use Command, Shift, and V, and model requests stay on this Mac.")
        #expect(cards(ExplainSetupDraw.plan(key: "Command-Shift-V", local: "On")) == ["Explain", "Key: Command-Shift-V", "Local: On"])
        #expect(cards(ExplainSetupDraw.plan(key: "Fn", local: "Off")) == ["Explain", "Can't"])
        #expect(ExplainSetupAsk.line(key: "Command-Shift-Space", local: "Maybe") == "I can't read the visual explanation settings.")
    }

    @Test func pointingKeysStayOffThisAsk() {
        #expect(ExplainSetupAsk.matches("how's the explanation set"))
        #expect(ExplainSetupAsk.matches("Hey Zeus, is explanation local only?"))
        #expect(ExplainSetupAsk.matches("explanation settings"))
        #expect(!ExplainSetupAsk.matches("which pointing keys"))
        #expect(!ExplainSetupAsk.matches("which talk microphone"))
        #expect(!ExplainSetupAsk.matches("what's the halo entrance"))
        #expect(!ExplainSetupAsk.matches("how's flick set"))
    }
}
