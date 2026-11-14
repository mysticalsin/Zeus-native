import Foundation
import Testing
@testable import ZeusCore

@Suite("Diagnostics redactor")
struct DiagnosticsRedactorTests {
    private func redact(_ text: String) -> String { DiagnosticsRedactor.redact(text, home: "/Users/nobody") }

    @Test func prefixedEnvStyleSecretsAreMasked() {
        let mask = DiagnosticsRedactor.mask
        #expect(redact("DUST_API_KEY=abc123def456ghij") == "DUST_API_KEY=\(mask)")
        #expect(redact("GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx") == "GITLAB_TOKEN=\(mask)")
        #expect(redact("AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY") == "AWS_SECRET_ACCESS_KEY=\(mask)")
        #expect(redact("export X_API_KEY=abc") == "export X_API_KEY=\(mask)")
        #expect(redact("DJANGO_SECRET_KEY: 'hunter2hunter2'") == "DJANGO_SECRET_KEY: '\(mask)")
        #expect(redact("db_password=hunter2 and APP_TOKEN=zzz") == "db_password=\(mask) and APP_TOKEN=\(mask)")
    }

    @Test func unprefixedPairsStillWork() {
        let mask = DiagnosticsRedactor.mask
        #expect(redact("api_key=abc") == "api_key=\(mask)")
        #expect(redact("token=abc123def") == "token=\(mask)")
        #expect(redact("Authorization: Bearer abcdefghijkl1234") == "Authorization: \(mask)")
        #expect(redact("x-api-key: abc") == "x-api-key: \(mask)")
    }

    @Test func normalWordsAreLeftAlone() {
        for text in ["The tokenizer ran: ok", "max_tokens=512 and secretary: Ana", "keyboard=us password reset needed",
                     "monkey=banana", "passwordless: yes", "keep_alive=true", "token count is 12", "secrets are hard"] {
            #expect(redact(text) == text, "\(text)")
        }
    }

    @Test func redactingTwiceChangesNothing() {
        let once = redact("GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx and DUST_API_KEY=abc123def456ghij")
        #expect(redact(once) == once)
    }

    @Test func aLongRunOfWordCharactersIsMaskedQuickly() {
        let long = String(repeating: "a", count: 200_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = redact(long) }
        #expect(elapsed < .seconds(5))
    }
}
