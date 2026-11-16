import Foundation
import Testing
@testable import ZeusCore

@Suite struct TalkDrawPolicyTests {
    @Test func consentOffSendsNoImages() {
        #expect(!TalkDrawPolicy.wantsImages(consent: false, shots: 0))
        #expect(!TalkDrawPolicy.wantsImages(consent: false, shots: 2))
    }

    @Test func consentOnWithNoShotsSendsNoImages() {
        #expect(!TalkDrawPolicy.wantsImages(consent: true, shots: 0))
    }

    @Test func consentOnWithShotsWantsImages() {
        #expect(TalkDrawPolicy.wantsImages(consent: true, shots: 1))
        #expect(TalkDrawPolicy.wantsImages(consent: true, shots: 3))
    }

    @Test func onlyAWinnerThatSawPixelsMayDraw() {
        #expect(TalkDrawPolicy.accepts(winner: "claude"))
        #expect(TalkDrawPolicy.accepts(winner: "anthropic-api"))
        for blind in ["codex", "gemini", "ollama", "openai", "grok", "cursor-agent", "", nil] as [String?] {
            #expect(!TalkDrawPolicy.accepts(winner: blind), "\(blind ?? "nil")")
        }
    }

    @Test func aRequestKeepsItsDrawImageFlagThroughWith() {
        let request = BrainRequest(transcript: "x", systemPrompt: "s", carriesDrawImage: true)
        #expect(request.carriesDrawImage)
        #expect(request.with(deep: true, firstTextBudget: 8).carriesDrawImage)
        #expect(!BrainRequest(transcript: "x", systemPrompt: "s").carriesDrawImage)
    }
}
