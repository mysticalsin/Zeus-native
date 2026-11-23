import Testing
@testable import ZeusCore

@Suite("Connection fallback")
struct ConnectionFallbackTests {
    @Test func anEmptyOfferDoesNotInventAProvider() {
        #expect(ConnectionFallback.selection(saved: "Claude Code", offered: []) == nil)
        #expect(ConnectionFallback.chain(chosen: "Claude Code", offered: []).isEmpty)
        #expect(ConnectionFallback.spokenChain(chosen: "Claude Code", offered: []) == "No agent is offered for new chats.")
    }

    @Test func aSavedChoiceLeadsWhenItIsOffered() {
        let offered = ["Claude Code", "Codex"]
        #expect(ConnectionFallback.selection(saved: "Codex", offered: offered) == "Codex")
        #expect(ConnectionFallback.chain(chosen: "Codex", offered: offered) == ["Codex", "Claude Code"])
        #expect(ConnectionFallback.spokenChain(chosen: "Codex", offered: offered) == "New chats use Codex. If that connection is not ready, Claude Code.")
    }

    @Test func aMissingChoiceFallsBackToTheFirstOfferedConnection() {
        let offered = ["Codex", "Gemini"]
        #expect(ConnectionFallback.selection(saved: "Claude Code", offered: offered) == "Codex")
        #expect(ConnectionFallback.selection(saved: nil, offered: offered) == "Codex")
        #expect(ConnectionFallback.spokenChain(chosen: "Claude Code", offered: offered) == "New chats use Codex. If that connection is not ready, Gemini.")
    }
}
