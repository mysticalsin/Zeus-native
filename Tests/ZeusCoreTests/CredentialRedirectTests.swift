import Foundation
import Testing
@testable import ZeusCore

@Suite("Credential redirects")
struct CredentialRedirectTests {
    private let original = URL(string: "https://api.example.test/v1/messages")!
    private let headers = ["x-api-key": "example-secret", "Accept": "application/json", "Authorization": "Bearer example-secret"]

    @Test func aCrossOriginRedirectIsRefused() {
        let cross = URL(string: "https://other.example.test/steal")!
        #expect(CredentialRedirect.forwarded(proposed: cross, from: original, headers: headers) == nil)
    }

    @Test func aSameOriginRedirectDropsCredentialHeaders() {
        let same = URL(string: "https://api.example.test/v1/models")!
        let forwarded = CredentialRedirect.forwarded(proposed: same, from: original, headers: headers)
        #expect(forwarded?.url == same)
        #expect(forwarded?.headers["x-api-key"] == nil)
        #expect(forwarded?.headers["Authorization"] == nil)
        #expect(forwarded?.headers["Accept"] == "application/json")
    }

    @Test func anHTTPSDowngradeIsRefused() {
        let plain = URL(string: "http://api.example.test/v1/models")!
        #expect(CredentialRedirect.forwarded(proposed: plain, from: original, headers: headers) == nil)
    }
}
