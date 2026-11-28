import Testing
@testable import ZeusCore

struct OfferSetupDrawTests {
    private func cards(_ plan: OfferSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func bothAgentsFollowOffer() {
        let usual = OfferSetupDraw.plan(claude: "On", claudeLink: "Not connected", codex: "On", codexLink: "Not connected")
        #expect(cards(usual) == ["Offer", "Claude: On", "Claude link: Not connected", "Codex: On", "Codex link: Not connected"])
        #expect(OfferSetupAsk.line(claude: "On", claudeLink: "Not connected", codex: "On", codexLink: "Not connected") == "Claude Code is offered and is not connected. Codex is offered and is not connected.")
        #expect(usual.boltCaption(at: 0) == "Offer")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 4 + 0.001) == "Codex link: Not connected")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 4 + 0.001) == TalkDraw.Point(x: 920, y: 390))
        #expect(OfferSetupAsk.line(claude: "On", claudeLink: "Connected", codex: "Off", codexLink: "Connected") == "Claude Code is offered and is connected. Codex is not offered and is connected.")
        #expect(cards(OfferSetupDraw.plan(claude: "Off", claudeLink: "Not connected", codex: "Off", codexLink: "Not connected")) == ["Offer", "Claude: Off", "Claude link: Not connected", "Codex: Off", "Codex link: Not connected"])
        #expect(cards(OfferSetupDraw.plan(claude: "Maybe", claudeLink: "Not connected", codex: "On", codexLink: "Not connected")) == ["Offer", "Can't"])
        #expect(OfferSetupAsk.line(claude: "On", claudeLink: "Broken", codex: "On", codexLink: "Not connected") == "I can't read which agents are offered.")
    }

    @Test func theDefaultAgentStaysOffThisAsk() {
        #expect(OfferSetupAsk.matches("which agents are offered"))
        #expect(OfferSetupAsk.matches("Hey Zeus, is claude offered?"))
        #expect(OfferSetupAsk.matches("new chat settings"))
        #expect(!OfferSetupAsk.matches("which default agent"))
        #expect(!OfferSetupAsk.matches("which coding agent"))
        #expect(!OfferSetupAsk.matches("how's automation set"))
        #expect(!OfferSetupAsk.matches("how's proactive set"))
    }
}
