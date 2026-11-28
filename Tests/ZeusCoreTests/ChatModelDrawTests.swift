import Testing
@testable import ZeusCore

struct ChatModelDrawTests {
    private func cards(_ plan: ChatModelDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func aFreshInstallUsesClaudeAndNeedsNoKey() {
        let usual = ChatModelDraw.plan(model: "Claude Code default", key: "Built-in")
        #expect(cards(usual) == ["Reply", "Model: Claude Code default", "Key: Built-in"])
        #expect(ChatModelAsk.line(model: "Claude Code default", key: "Built-in") == "The chat model is Claude Code default, and it needs no key.")
        #expect(usual.boltCaption(at: 0) == "Reply")
        #expect(usual.boltCaption(at: ExplainBeatSchedule.gap * 2 + 0.001) == "Key: Built-in")
        #expect(usual.guideBolt(at: ExplainBeatSchedule.gap * 2 + 0.001) == TalkDraw.Point(x: 920, y: 250))
        #expect(ChatModelAsk.line(model: "gpt-5-mini", key: "Saved") == "The chat model is gpt-5-mini, and a key is saved.")
        #expect(ChatModelAsk.line(model: "claude-haiku-4-5", key: "None") == "The chat model is claude-haiku-4-5, and no key is saved.")
        #expect(ChatModelAsk.line(model: "claude-sonnet-4-5", key: "Saved") == "The chat model is claude-sonnet-4-5, and a key is saved.")
        #expect(cards(ChatModelDraw.plan(model: "opus", key: "None")) == ["Reply", "Can't"])
        #expect(ChatModelAsk.line(model: "Claude Code default", key: "Secret") == "I can't read the chat model.")
    }

    @Test func whoAnswersStaysOffThisAsk() {
        #expect(ChatModelAsk.matches("which chat model"))
        #expect(ChatModelAsk.matches("Hey Zeus, how is the chat model set?"))
        #expect(ChatModelAsk.matches("does the chat model need a key"))
        #expect(!ChatModelAsk.matches("who answers"))
        #expect(!ChatModelAsk.matches("which model answers"))
        #expect(!ChatModelAsk.matches("how is any llm set"))
        #expect(!ChatModelAsk.matches("which voice keys are saved"))
    }
}
