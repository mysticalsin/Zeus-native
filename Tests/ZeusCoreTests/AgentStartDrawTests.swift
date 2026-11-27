import Testing
@testable import ZeusCore

struct AgentStartDrawTests {
    @Test func aStartShowsBuildingThenTheToolAndTheTask() throws {
        let plan = try #require(AgentStartDraw.plan(tool: "Claude Code", project: "Zeus", task: "fix the build"))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Building", "Claude Code in Zeus", "fix the build"])
        #expect(plan.boltCaption(at: 0) == "Building")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap) == "Claude Code in Zeus")
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 2) == "fix the build")
        #expect(plan.guideBolt(at: 0) == TalkDraw.Point(x: 320, y: 320))
        #expect(plan.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
    }

    @Test func aBlankToolIsNotDrawnAndABlankTaskIsOmitted() throws {
        #expect(AgentStartDraw.plan(tool: "  ", project: "Zeus", task: "fix the build") == nil)
        let plan = try #require(AgentStartDraw.plan(tool: "Codex", project: nil, task: "  "))
        let cards = plan.draw.marks.compactMap { mark -> String? in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
        #expect(cards == ["Building", "Codex"])
        #expect(plan.boltCaption(at: ExplainBeatSchedule.gap * 3) == "Codex")
    }
}
