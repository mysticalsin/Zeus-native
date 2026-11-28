import Testing
@testable import ZeusCore

struct ProviderDrawTests {
    private func cards(_ plan: ProviderDraw) -> [String] {
        plan.draw.marks.compactMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    @Test func theMenuTitleIsTheSecondCard() {
        let claude = ProviderDraw.plan(word: "Claude CLI")
        #expect(cards(claude) == ["Provider", "Claude CLI"])
        #expect(ProviderAsk.line(word: "Claude CLI") == "Claude answers in chat.")
        #expect(claude.boltCaption(at: 0) == "Provider")
        #expect(claude.boltCaption(at: ExplainBeatSchedule.gap) == "Claude CLI")
        #expect(claude.guideBolt(at: ExplainBeatSchedule.gap) == TalkDraw.Point(x: 920, y: 180))
        #expect(ProviderAsk.line(word: "OpenAI") == "OpenAI answers in chat.")
        #expect(ProviderAsk.line(word: "Anthropic") == "Anthropic answers in chat.")
        #expect(cards(ProviderDraw.plan(word: "Banana")) == ["Provider", "Can't"])
        #expect(ProviderAsk.line(word: "") == "I can't read who answers.")
    }

    @Test func theAgentsAndTheChatShortcutStayOffThisAsk() {
        #expect(ProviderAsk.matches("who answers"))
        #expect(ProviderAsk.matches("Hey Zeus, who's answering?"))
        #expect(ProviderAsk.matches("which model answers"))
        #expect(!ProviderAsk.matches("who is working"))
        #expect(!ProviderAsk.matches("what's the chat shortcut"))
        #expect(!ProviderAsk.matches("what's the pointing key"))
        #expect(!ProviderAsk.matches("which voice is this"))
    }
}
