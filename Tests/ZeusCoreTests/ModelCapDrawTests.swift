import Testing
@testable import ZeusCore

struct ModelCapDrawTests {
    private func cards(_ plan: ModelCapDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshCapStaysAtSonnet() {
        let usual = ModelCapDraw.plan(size: "Sonnet", pin: "None")
        #expect(cards(usual) == ["Cap", "Size: Sonnet", "Pins: None"])
        #expect(ModelCapAsk.line(size: "Sonnet", pin: "None") == "Zeus stays at Sonnet or smaller, and no model pin is saved.")
        #expect(usual.boltCaption(at: 0) == "Cap")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Pins: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ModelCapAsk.line(size: "Sonnet", pin: "Set") == "Zeus stays at Sonnet or smaller, and a model pin is saved.")
        #expect(ModelCapAsk.line(size: "Sonnet", pin: "Refused") == "Zeus stays at Sonnet or smaller, and a model pin was refused.")
        #expect(cards(ModelCapDraw.plan(size: "Opus", pin: "None")) == ["Cap", "Can't"])
        #expect(ModelCapAsk.line(size: "Sonnet", pin: "Maybe") == "I can't read the model cap.")
    }

    @Test func theChatModelStaysOffThisAsk() {
        #expect(ModelCapAsk.matches("which models does zeus use"))
        #expect(ModelCapAsk.matches("Hey Zeus, does Zeus stay at Sonnet?"))
        #expect(ModelCapAsk.matches("is a model pin saved"))
        #expect(!ModelCapAsk.matches("which chat model"))
        #expect(!ModelCapAsk.matches("how is coding set"))
        #expect(!ModelCapAsk.matches("do screen shares show zeus"))
        #expect(!ModelCapAsk.matches("do permission requests always show"))
    }
}
