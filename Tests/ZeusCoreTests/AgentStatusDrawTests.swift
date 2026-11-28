import Testing
@testable import ZeusCore

struct AgentStatusDrawTests {
    private func cards(_ plan: AgentStatusDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func oneAgentDrawsTheNameThenTheState() {
        let plan = AgentStatusDraw.plan(name: "Claude", state: "Working")
        #expect(plan.map(cards) == ["Agents", "Claude", "Working"])
        #expect(AgentStatusAsk.line(name: "Claude", state: "Working") == "Claude is working.")
        #expect(AgentStatusAsk.line(name: "Claude", state: "Needs you") == "Claude needs you.")
        #expect(plan?.boltCaption(at: 0) == "Agents")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap) == "Claude")
        #expect(plan?.boltCaption(at: ExplainBeatSchedule.gap * 2) == "Working")
        #expect(plan?.guideBolt(at: ExplainBeatSchedule.gap * 2) == TalkDraw.Point(x: 920, y: 250))
        #expect(AgentStatusDraw.plan(name: " ", state: "Working") == nil)
        #expect(AgentStatusDraw.plan(name: "Claude", state: " ") == nil)
    }

    @Test func severalAgentsDrawTheCountAndNobodyRunningDrawsNone() {
        let plan = AgentStatusDraw.plan(count: 2, working: 1)
        #expect(plan.map(cards) == ["Agents", "2 agents", "1 working"])
        #expect(AgentStatusAsk.line(count: 2, working: 1) == "2 agents, 1 working.")
        #expect(AgentStatusDraw.plan(count: 3, working: 0).map(cards) == ["Agents", "3 agents", "Idle"])
        #expect(AgentStatusAsk.line(count: 3, working: 0) == "3 agents are running.")
        #expect(AgentStatusDraw.plan(count: 1, working: 1) == nil)
        #expect(cards(AgentStatusDraw.none()) == ["Agents", "None"])
        #expect(AgentStatusAsk.none == "No agents are running.")
        #expect(AgentStatusAsk.matches("what are my agents doing"))
        #expect(AgentStatusAsk.matches("Hey Zeus, who's working?"))
        #expect(!AgentStatusAsk.matches("stop all agents"))
        #expect(!AgentStatusAsk.matches("read my note"))
        #expect(!AgentStatusAsk.matches("what's the date"))
    }
}
