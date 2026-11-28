import Testing
@testable import ZeusCore

struct GatewayDrawTests {
    private func cards(_ plan: GatewayDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoEndpoint() {
        let usual = GatewayDraw.plan(address: "None", model: "None", key: "None", link: "Off")
        #expect(cards(usual) == ["Gateway", "Address: None", "Model: None", "Key: None", "Link: Off"])
        #expect(GatewayAsk.line(address: "None", model: "None", key: "None", link: "Off") == "No endpoint address is set, no model is set, no key is saved, and the link is off.")
        #expect(usual.boltCaption(at: 0) == "Gateway")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Link: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(GatewayAsk.line(address: "Set", model: "Set", key: "Saved", link: "Local") == "An endpoint address is set, a model is set, a key is saved, and the link stays on this Mac.")
        #expect(GatewayAsk.line(address: "Set", model: "Set", key: "Again", link: "Remote") == "An endpoint address is set, a model is set, the key must be pasted again, and the link leaves this Mac.")
        #expect(GatewayAsk.line(address: "Set", model: "None", key: "None", link: "Blocked") == "An endpoint address is set, no model is set, no key is saved, and the link is blocked.")
        #expect(cards(GatewayDraw.plan(address: "https://example.com", model: "None", key: "None", link: "Off")) == ["Gateway", "Can't"])
        #expect(GatewayAsk.line(address: "None", model: "gpt", key: "None", link: "Off") == "I can't read the model endpoint.")
    }

    @Test func explanationSettingsStayOffThisAsk() {
        #expect(GatewayAsk.matches("how is any llm set"))
        #expect(GatewayAsk.matches("Hey Zeus, does any llm have a key?"))
        #expect(GatewayAsk.matches("where does any llm send"))
        #expect(!GatewayAsk.matches("how is the explanation set"))
        #expect(!GatewayAsk.matches("is explanation local only"))
        #expect(!GatewayAsk.matches("how is the companion set"))
        #expect(!GatewayAsk.matches("which pointing provider"))
    }
}
