import Foundation
import Testing
@testable import ZeusCore

@Suite("Provider failure message")
struct ProviderFailureMessageTests {
    @Test func aBadKeyAsksForANewKeyAndDoesNotBlameCredits() {
        let kind = ProviderFailureMessage.kind(status: 401, detail: "invalid_api_key")
        #expect(kind == .badKey)
        let text = ProviderFailureMessage.message(label: "ElevenLabs", kind: kind) ?? ""
        #expect(text.contains("Paste a new key"))
        #expect(!text.lowercased().contains("quota"))
        #expect(!text.contains("credits"))
    }

    @Test func usedUpCreditsSayTheCreditsAreUsedUpAndTheNextVoiceSpeaksUntilThePauseEnds() {
        for (status, detail) in [(401, "quota_exceeded"), (402, ""), (429, "quota_exceeded")] {
            let kind = ProviderFailureMessage.kind(status: status, detail: detail)
            #expect(kind == .creditsUsedUp, "status \(status) detail \(detail)")
        }
        let text = ProviderFailureMessage.message(label: "ElevenLabs", kind: .creditsUsedUp) ?? ""
        #expect(text.contains("credits are used up"))
        #expect(text.contains("next voice until the pause ends"))
        #expect(!text.contains("Paste a new key"))
    }

    @Test func aPlain401WithNoDetailIsABadKeyAndOtherRefusalsAreLeftToTheCaller() {
        #expect(ProviderFailureMessage.kind(status: 401, detail: "") == .badKey)
        #expect(ProviderFailureMessage.kind(status: 403, detail: "") == .badKey)
        #expect(ProviderFailureMessage.kind(status: 429, detail: "too_many_concurrent_requests") == .rateLimited)
        #expect(ProviderFailureMessage.kind(status: 500, detail: "") == .other)
        #expect(ProviderFailureMessage.message(label: "ElevenLabs", kind: .rateLimited) == nil)
        #expect(ProviderFailureMessage.message(label: "ElevenLabs", kind: .other) == nil)
    }

    @Test func noMessageHasADash() {
        for kind in [ProviderFailureMessage.Kind.badKey, .creditsUsedUp] {
            #expect(!(ProviderFailureMessage.message(label: "ElevenLabs", kind: kind) ?? "").contains("\u{2014}"))
        }
    }
}
