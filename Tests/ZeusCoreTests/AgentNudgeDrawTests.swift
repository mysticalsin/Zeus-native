import Testing
@testable import ZeusCore

struct AgentNudgeDrawTests {
    private func cards(_ plan: AgentNudgeDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theSwitchAndWaitFollowNudge() {
        let usual = AgentNudgeDraw.plan(work: "Off", after: "10 min")
        #expect(cards(usual) == ["Nudge", "Work: Off", "After: 10 min"])
        #expect(AgentNudgeAsk.line(work: "Off", after: "10 min") == "Nudges are off, and a pane is stalled after 10 min.")
        #expect(usual.boltCaption(at: 0) == "Nudge")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "After: 10 min")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(AgentNudgeAsk.line(work: "On", after: "30 min") == "Nudges are on, and a pane is stalled after 30 min.")
        #expect(cards(AgentNudgeDraw.plan(work: "On", after: "5 min")) == ["Nudge", "Work: On", "After: 5 min"])
        #expect(cards(AgentNudgeDraw.plan(work: "On", after: "7 min")) == ["Nudge", "Can't"])
        #expect(AgentNudgeAsk.line(work: "Maybe", after: "10 min") == "I can't read the agent nudge.")
    }

    @Test func insomniaSettingsAndAgentNoticesStayOffThisAsk() {
        #expect(AgentNudgeAsk.matches("how's the nudge set"))
        #expect(AgentNudgeAsk.matches("Hey Zeus, do you nudge stalled agents?"))
        #expect(AgentNudgeAsk.matches("nudge settings"))
        #expect(!AgentNudgeAsk.matches("how's insomnia set"))
        #expect(!AgentNudgeAsk.matches("when is an agent stuck"))
        #expect(!AgentNudgeAsk.matches("what are my agents doing"))
        #expect(!AgentNudgeAsk.matches("how's recording set"))
    }
}
