import Testing
@testable import ZeusCore

struct FreezeSetupDrawTests {
    private func cards(_ plan: FreezeSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallHasNoRuleAndFreezesNothing() {
        let usual = FreezeSetupDraw.plan(rule: "Not set up", frozen: "0")
        #expect(cards(usual) == ["Rule", "Rule: Not set up", "Frozen: 0"])
        #expect(FreezeSetupAsk.line(rule: "Not set up", frozen: "0") == "The admin rule is not set up, and no apps freeze when the lid closes.")
        #expect(usual.boltCaption(at: 0) == "Rule")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Frozen: 0")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(FreezeSetupAsk.line(rule: "Ready", frozen: "2") == "The admin rule is ready, and 2 apps freeze when the lid closes.")
        #expect(FreezeSetupAsk.line(rule: "Needs repair", frozen: "1") == "The admin rule needs repair, and 1 app freezes when the lid closes.")
        #expect(cards(FreezeSetupDraw.plan(rule: "Ready", frozen: "0")) == ["Rule", "Rule: Ready", "Frozen: 0"])
        #expect(cards(FreezeSetupDraw.plan(rule: "Missing", frozen: "0")) == ["Rule", "Can't"])
        #expect(FreezeSetupAsk.line(rule: "Ready", frozen: "Slack") == "I can't read the lid-closed rule.")
    }

    @Test func theHotspotStaysOffThisAsk() {
        #expect(FreezeSetupAsk.matches("how is the admin rule set"))
        #expect(FreezeSetupAsk.matches("Hey Zeus, how many apps freeze?"))
        #expect(FreezeSetupAsk.matches("insomnia freeze settings"))
        #expect(!FreezeSetupAsk.matches("how is insomnia set"))
        #expect(!FreezeSetupAsk.matches("how is the hotspot set"))
        #expect(!FreezeSetupAsk.matches("how is the nudge set"))
        #expect(!FreezeSetupAsk.matches("how many apps are muted"))
    }
}
