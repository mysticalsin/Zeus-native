import Testing
@testable import ZeusCore

struct NotifySetupDrawTests {
    private func cards(_ plan: NotifySetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func errorsStallAndQuietFollowNotify() {
        let usual = NotifySetupDraw.plan(errors: "On", stuck: "5 min", quiet: "On")
        #expect(cards(usual) == ["Notify", "Errors: On", "Stuck: 5 min", "Quiet: On"])
        #expect(NotifySetupAsk.line(errors: "On", stuck: "5 min", quiet: "On") == "Errors are on, an agent is stuck after 5 min, and quiet while sharing is on.")
        #expect(usual.boltCaption(at: 0) == "Notify")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 3 + 0.001) == "Quiet: On")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 3 + 0.001) == TalkDraw.Point(x: 920, y: 320))
        #expect(NotifySetupAsk.line(errors: "Off", stuck: "2 min", quiet: "Off") == "Errors are off, an agent is stuck after 2 min, and quiet while sharing is off.")
        #expect(cards(NotifySetupDraw.plan(errors: "On", stuck: "15 min", quiet: "On")) == ["Notify", "Errors: On", "Stuck: 15 min", "Quiet: On"])
        #expect(cards(NotifySetupDraw.plan(errors: "On", stuck: "7 min", quiet: "On")) == ["Notify", "Can't"])
        #expect(NotifySetupAsk.line(errors: "Maybe", stuck: "5 min", quiet: "On") == "I can't read the agent notices.")
    }

    @Test func waitingNotificationsStayOffThisAsk() {
        #expect(NotifySetupAsk.matches("how's agent notices set"))
        #expect(NotifySetupAsk.matches("Hey Zeus, when is an agent stuck?"))
        #expect(NotifySetupAsk.matches("agent notification settings"))
        #expect(!NotifySetupAsk.matches("notifications"))
        #expect(!NotifySetupAsk.matches("how many alerts"))
        #expect(!NotifySetupAsk.matches("how's coding set"))
        #expect(!NotifySetupAsk.matches("what are my agents doing"))
    }
}
