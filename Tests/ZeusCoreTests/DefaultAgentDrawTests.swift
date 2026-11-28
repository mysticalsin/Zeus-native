import Testing
@testable import ZeusCore

struct DefaultAgentDrawTests {
    private func cards(_ plan: DefaultAgentDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theAgentFollowsNew() {
        let usual = DefaultAgentDraw.plan(agent: "Claude Code")
        #expect(cards(usual) == ["New", "Agent: Claude Code"])
        #expect(DefaultAgentAsk.line(agent: "Claude Code") == "New chats open with Claude Code.")
        #expect(usual.boltCaption(at: 0) == "New")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap + 0.001) == "Agent: Claude Code")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap + 0.001) == TalkDraw.Point(x: 920, y: 180))
        #expect(DefaultAgentAsk.line(agent: "Codex") == "New chats open with Codex.")
        #expect(cards(DefaultAgentDraw.plan(agent: "Codex")) == ["New", "Agent: Codex"])
        #expect(cards(DefaultAgentDraw.plan(agent: "Gemini")) == ["New", "Can't"])
        #expect(DefaultAgentAsk.line(agent: "Cursor Agent") == "I can't read the default agent.")
    }

    @Test func codingAndThePickerStayOffThisAsk() {
        #expect(DefaultAgentAsk.matches("which default agent"))
        #expect(DefaultAgentAsk.matches("Hey Zeus, who opens a new chat?"))
        #expect(DefaultAgentAsk.matches("default agent settings"))
        #expect(!DefaultAgentAsk.matches("which coding agent"))
        #expect(!DefaultAgentAsk.matches("what's the coding agent"))
        #expect(!DefaultAgentAsk.matches("what's the agent picker shortcut"))
        #expect(!DefaultAgentAsk.matches("how's jev set"))
    }
}
