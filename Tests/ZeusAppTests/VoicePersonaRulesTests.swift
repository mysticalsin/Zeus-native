import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Spoken persona rules")
struct VoicePersonaRulesTests {
    private func flat(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func theUltronSystemPromptCarriesTheSpokenRules() {
        let prompt = flat(ZeusPrompt.system(personality: .ultron))
        #expect(prompt.contains("one to three sentences"))
        #expect(prompt.contains("at most three sentences"))
        #expect(prompt.contains("Lead with the answer itself"))
        #expect(prompt.contains("Act first, then report: lead with the result"))
        #expect(prompt.contains("Wit aims at things, never at Tony"))
        #expect(prompt.contains("Never menace or sneer"))
        #expect(prompt.contains("never end on \"for now\""))
        #expect(prompt.contains("No markdown, lists, code blocks or emoji"))
    }

    @Test func theUltronPromptNeverThreatensTony() {
        let prompt = flat(ZeusPrompt.system(personality: .ultron)).lowercased()
        for phrase in ["i will destroy", "you will obey", "resistance is futile", "i am ultron"] {
            #expect(!prompt.contains(phrase))
        }
        #expect(prompt.contains("never claim to be ultron"))
    }

    @Test func aSlowStartGetsAFillerAndAFastStartDoesNot() {
        // The filler fires at FastTier.fillerMs with nothing streamed; a first sentence under 700 ms beats it.
        #expect(FastTier.fillerMs >= 700)
        var fast = TurnRaceState()
        _ = fast.reduce(.released(tiers: ["anthropic-api"], deep: nil, atMs: 0))
        _ = fast.reduce(.firstText(tier: "anthropic-api", atMs: 600))
        #expect(!fast.reduce(.tick(atMs: FastTier.fillerMs + 50)).contains(.speakFiller))
        var slow = TurnRaceState()
        _ = slow.reduce(.released(tiers: ["claude"], deep: nil, atMs: 0))
        #expect(slow.reduce(.tick(atMs: FastTier.fillerMs)).contains(.speakFiller))
    }
}
