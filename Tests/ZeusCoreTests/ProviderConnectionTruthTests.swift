import Foundation
import Testing
@testable import ZeusCore

@Suite("Provider connection truth")
struct ProviderConnectionTruthTests {
    @Test func installedCursorAndGeminiRespectTheirOwnOfferSwitches() {
        let installed: Set<CodingTool> = [.gemini, .cursorAgent]
        #expect(NewChatAgents.offered(claude: false, codex: true, gemini: false, cursor: true,
                                     installed: installed) == [.codex, .cursorAgent])
        #expect(NewChatAgents.offered(claude: false, codex: true, gemini: true, cursor: false,
                                     installed: installed) == [.codex, .gemini])
        #expect(NewChatAgents.offered(claude: false, codex: false, gemini: true, cursor: true,
                                     installed: []) == [])
    }

    @Test func disablingEveryOfferDoesNotSilentlyRestoreClaude() {
        #expect(NewChatAgents.offered(claude: false, codex: false, gemini: false, cursor: false,
                                     installed: [.claude, .codex, .gemini, .cursorAgent]).isEmpty)
    }

    @Test func onlyImplementedChatLaunchersExposeOfferSettings() {
        #expect(AIProvider.allCases.filter(\.supportsNewChats) == [.claudeCode, .codex, .cursor, .gemini])
        for provider in [AIProvider.chatgpt, .grok, .ollama, .lmStudio, .anyLLM] {
            #expect(!provider.supportsNewChats)
        }
    }

    @Test func unknownAuthNeverClaimsTheProviderIsSignedIn() {
        for provider in [AIProvider.claudeCode, .codex, .cursor, .gemini] {
            let unknown = AIConnectFlow.hookConnectionMessage(provider, signedIn: nil)
            #expect(unknown.contains("could not be verified"))
            #expect(!unknown.contains("is signed in"))
            #expect(AIConnectFlow.hookConnectionMessage(provider, signedIn: false).contains("isn't signed in"))
            #expect(AIConnectFlow.hookConnectionMessage(provider, signedIn: true).contains("is signed in"))
        }
    }

    @Test func appOpenDescriptionsDoNotPromiseUnsupportedPromptHandoff() {
        for provider in [AIProvider.chatgpt, .grok] {
            #expect(provider.blurb.contains("Prompt handoff is not supported"))
        }
    }

    @Test func anthropicMessagesAPIIsNotOfferedAsAnOpenAICompatiblePreset() {
        #expect(!AIConnectFlow.endpointPresets.contains { URL(string: $0.baseURL)?.host == "api.anthropic.com" })
        #expect(AIConnectFlow.endpointPresets.contains { $0.title == "OpenAI" })
    }
}
