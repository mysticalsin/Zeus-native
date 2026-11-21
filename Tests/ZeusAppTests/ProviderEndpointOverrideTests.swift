import Foundation
import Testing
@testable import Zeus

/// A set key stays on the production URL. The loopback stub is only for a provider with no key.
#if DEBUG
@Suite("Provider endpoint override")
struct ProviderEndpointOverrideTests {
    private let production = URL(string: "https://api.openai.com/v1")!
    private let loopback = [
        "ZEUS_DEBUG_PROVIDER_STUB": "1",
        "ZEUS_DEBUG_PROVIDER_BASE_URL": "http://127.0.0.1:59999/v1",
    ]

    @Test func aSetKeyStaysOnTheProductionURL() {
        let got = ProviderEndpointOverride.resolved(production: production, key: "sk-live", environment: loopback)
        #expect(got == production)
    }

    @Test func aBlankKeyIsNotACredential() {
        let got = ProviderEndpointOverride.resolved(production: production, key: "   ", environment: loopback)
        #expect(got == production)
    }

    @Test func noKeyUsesTheLoopbackStub() {
        let got = ProviderEndpointOverride.resolved(production: production, key: nil, environment: loopback)
        #expect(got.absoluteString == "http://127.0.0.1:59999/v1")
    }

    @Test func anEmptyKeyMayUseTheStub() {
        let got = ProviderEndpointOverride.resolved(production: production, key: "", environment: loopback)
        #expect(got.absoluteString == "http://127.0.0.1:59999/v1")
    }

    @Test func noKeyWithoutTheSentinelStaysOnProduction() {
        let quiet = ["ZEUS_DEBUG_PROVIDER_BASE_URL": "http://127.0.0.1:59999/v1"]
        let got = ProviderEndpointOverride.resolved(production: production, key: nil, environment: quiet)
        #expect(got == production)
    }

    @Test func noKeyRejectsAnythingButHTTPLoopback() {
        let rejected = [
            "http://example.com/v1",
            "https://127.0.0.1:59999/v1",
            "http://localhost:59999/v1",
            "http://127.0.0.1.example/v1",
        ]
        for raw in rejected {
            let env = ["ZEUS_DEBUG_PROVIDER_STUB": "1", "ZEUS_DEBUG_PROVIDER_BASE_URL": raw]
            let got = ProviderEndpointOverride.resolved(production: production, key: nil, environment: env)
            #expect(got == production)
        }
    }
}
#endif
