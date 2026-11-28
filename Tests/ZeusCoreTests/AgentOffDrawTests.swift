import Testing
@testable import ZeusCore

struct AgentOffDrawTests {
    @Test func aBrowserAgentTurnedOffShowsOff() throws {
        let plan = try #require(AgentOffDraw.from(line: "the browser agent is off. Turn it on in Settings."))
        func cards(_ plan: AgentOffDraw) -> [String] {
            plan.draw.marks.compactMap { mark in
                if case .card(_, let text) = mark.shape { return text }
                return nil
            }
        }
        #expect(cards(plan) == ["Agent", "Off"])
        #expect(plan.boltCaption(at: 0) == "Agent")
        #expect(plan.boltCaption(at: 100) == "Off")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func notReadyAndNoAIAreNotThisCard() {
        #expect(AgentOffDraw.from(line: "") == nil)
        #expect(AgentOffDraw.from(line: "the browser agent is off. Turn it on in Settings, Features.") == nil)
        #expect(AgentOffDraw.from(line: "Zeus isn't ready yet.") == nil)
        #expect(AgentOffDraw.from(line: "no AI is connected. Connect one in Settings, Integrations.") == nil)
        #expect(AgentOffDraw.from(line: "Okay, I left it open.") == nil)
    }
}
