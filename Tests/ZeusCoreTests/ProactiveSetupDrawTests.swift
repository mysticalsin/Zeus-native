import Testing
@testable import ZeusCore

struct ProactiveSetupDrawTests {
    private func cards(_ plan: ProactiveSetupDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func briefAndDueFollowAhead() {
        let usual = ProactiveSetupDraw.plan(brief: "Off", due: "Off")
        #expect(cards(usual) == ["Ahead", "Brief: Off", "Due: Off"])
        #expect(ProactiveSetupAsk.line(brief: "Off", due: "Off") == "The morning brief is off, and a due to-do does not notify you.")
        #expect(usual.boltCaption(at: 0) == "Ahead")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Due: Off")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ProactiveSetupAsk.line(brief: "On", due: "On") == "The morning brief is on, and a due to-do notifies you.")
        #expect(ProactiveSetupAsk.line(brief: "On", due: "Off") == "The morning brief is on, and a due to-do does not notify you.")
        #expect(cards(ProactiveSetupDraw.plan(brief: "Off", due: "On")) == ["Ahead", "Brief: Off", "Due: On"])
        #expect(cards(ProactiveSetupDraw.plan(brief: "Maybe", due: "Off")) == ["Ahead", "Can't"])
        #expect(ProactiveSetupAsk.line(brief: "Off", due: "Yes") == "I can't read the proactive notices.")
    }

    @Test func waitingNotificationsStayOffThisAsk() {
        #expect(ProactiveSetupAsk.matches("how's proactive set"))
        #expect(ProactiveSetupAsk.matches("Hey Zeus, is the morning brief on?"))
        #expect(ProactiveSetupAsk.matches("proactive settings"))
        #expect(!ProactiveSetupAsk.matches("notifications"))
        #expect(!ProactiveSetupAsk.matches("how many notifications"))
        #expect(!ProactiveSetupAsk.matches("how's the explanation set"))
        #expect(!ProactiveSetupAsk.matches("which talk microphone"))
    }
}
