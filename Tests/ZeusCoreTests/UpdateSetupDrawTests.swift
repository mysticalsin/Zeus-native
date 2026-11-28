import Testing
@testable import ZeusCore

struct UpdateSetupDrawTests {
    private func cards(_ plan: UpdateSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallDoesNotCheck() {
        let usual = UpdateSetupDraw.plan(check: "Off", feed: "None")
        #expect(cards(usual) == ["Updates", "Check: Off", "Feed: None"])
        #expect(UpdateSetupAsk.line(check: "Off", feed: "None") == "Automatic updates are off, and no update feed is set.")
        #expect(usual.boltCaption(at: 0) == "Updates")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Feed: None")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(UpdateSetupAsk.line(check: "On", feed: "Set") == "Automatic updates are on, and an update feed is set.")
        #expect(cards(UpdateSetupDraw.plan(check: "On", feed: "None")) == ["Updates", "Check: On", "Feed: None"])
        #expect(cards(UpdateSetupDraw.plan(check: "Maybe", feed: "None")) == ["Updates", "Can't"])
        #expect(UpdateSetupAsk.line(check: "On", feed: "https://example.test") == "I can't read the update settings.")
    }

    @Test func checkingNowStaysOffThisAsk() {
        #expect(UpdateSetupAsk.matches("are automatic updates on"))
        #expect(UpdateSetupAsk.matches("Hey Zeus, does zeus check for updates?"))
        #expect(UpdateSetupAsk.matches("update settings"))
        #expect(!UpdateSetupAsk.matches("check for updates"))
        #expect(!UpdateSetupAsk.matches("which voice keys are saved"))
        #expect(!UpdateSetupAsk.matches("how is the world clock set"))
        #expect(!UpdateSetupAsk.matches("how is the hotspot set"))
    }
}
