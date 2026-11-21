import Testing
@testable import ZeusCore

@Suite("Agent supervision")
struct AgentSupervisionTests {
    private func step(_ title: String, _ kind: AgentSupervision.Step.Kind, _ ms: Int, added: Int = 0, removed: Int = 0, outcome: String? = nil) -> AgentSupervision.Step {
        AgentSupervision.Step(title: title, kind: kind, elapsedMs: ms, added: added, removed: removed, outcome: outcome)
    }

    @Test func aTimelineKeepsDurationsAndFileCounts() {
        let run = AgentSupervision.run(steps: [
            step("Read the spec", .step, 400),
            step("Edit the view", .tool, 1200, added: 20, removed: 4),
            step("Unit tests", .test, 800, outcome: "passed"),
        ], state: .working)
        #expect(run.steps.map(\.elapsedMs) == [400, 1200, 800])
        #expect(run.steps[1].fileCount == "+20 −4")
        #expect(run.steps[2].outcome == "passed")
        #expect(run.allow.isEmpty)
        #expect(AgentSupervision.showsUsage(tokens: nil, costCents: nil) == false)
    }

    @Test func waitingReusesAllowAndDeny() {
        let run = AgentSupervision.run(steps: [], state: .needsYou, risk: .high, tokens: 1200, costCents: 3)
        #expect(run.allow == "Allow")
        #expect(run.deny == "Deny")
        #expect(run.allowHolds)
        #expect(AgentSupervision.usage(tokens: 1200, costCents: 3) == "1200 tokens, 3¢")
    }

    @Test func aMissingLocalCostStaysHidden() {
        #expect(AgentSupervision.usage(tokens: nil, costCents: nil) == nil)
        #expect(AgentSupervision.usage(tokens: 10, costCents: nil) == "10 tokens")
    }

    @Test func severalAgentsShareOneLine() {
        #expect(AgentSupervision.overview([]) == "0 agents")
        #expect(AgentSupervision.overview([.working]) == "Working")
        #expect(AgentSupervision.overview([.working, .needsYou, .failed]) == "3 agents · 1 working · 1 waiting · 1 error")
        #expect(AgentSupervision.overview([.done, .done]) == "2 agents")
    }
}
