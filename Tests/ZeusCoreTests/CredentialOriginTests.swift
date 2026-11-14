import Foundation
import Testing
@testable import ZeusCore

/// A key is only ever sent to the address it was saved for.
@Suite("Credential origin binding")
struct CredentialOriginTests {
    private func origin(_ text: String) -> CredentialOrigin? { URL(string: text).flatMap(CredentialOrigin.init(url:)) }
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func schemeHostAndPortDefineTheOrigin() throws {
        let saved = try #require(origin("https://api.example.com/v1/chat/completions"))
        #expect(saved.matches(url("https://api.example.com/v1/models")), "the path does not matter")
        #expect(!saved.matches(url("https://other.example.com/v1")), "another host")
        #expect(!saved.matches(url("https://api.example.com:8443/v1")), "another port")
        #expect(!saved.matches(url("http://api.example.com/v1")), "another scheme")
        #expect(!saved.matches(url("https://example.com/v1")), "a parent domain")
        #expect(!saved.matches(url("https://evil.api.example.com/v1")), "a child domain")
    }

    @Test func caseDefaultPortsAndTrailingDotsDoNotChangeTheOrigin() throws {
        let saved = try #require(origin("https://API.Example.com/v1"))
        #expect(saved.matches(url("https://api.example.com:443/v1")))
        #expect(saved.matches(url("HTTPS://api.example.com./v1")))
        #expect(saved.matches(url("https://api.example.com../v1")))
        let local = try #require(origin("http://localhost:80/v1"))
        #expect(local.matches(url("http://LOCALHOST/v1")))
        #expect(local.matches(url("http://localhost./v1")))
        #expect(!local.matches(url("http://localhost:11434/v1")))
    }

    @Test func userinfoIsNeverAnOrigin() {
        #expect(origin("https://user@api.example.com/v1") == nil)
        #expect(origin("https://user:secret@api.example.com/v1") == nil)
        #expect(origin("https://:secret@api.example.com/v1") == nil)
    }

    @Test func aRequestWithUserinfoNeverMatches() throws {
        let saved = try #require(origin("https://api.example.com/v1"))
        #expect(!saved.matches(url("https://api.example.com@evil.example/v1")))
        #expect(!saved.matches(url("https://evil@api.example.com/v1")))
    }

    @Test func httpsIsRequiredExceptOnThisMac() {
        #expect(origin("http://api.example.com/v1") == nil)
        #expect(origin("http://10.0.0.5/v1") == nil)
        #expect(origin("ftp://api.example.com/v1") == nil)
        #expect(origin("api.example.com/v1") == nil)
        #expect(origin("http://localhost:11434/v1") != nil)
        #expect(origin("http://127.0.0.1:1234/v1") != nil)
        #expect(origin("http://[::1]:8080/v1") != nil)
        #expect(origin("https://api.example.com/v1") != nil)
    }

    @Test func aMissingHostIsNotAnOrigin() {
        #expect(origin("https:///v1") == nil)
        #expect(origin("https://./v1") == nil)
    }

    @Test func theStoredFormRoundTrips() throws {
        let saved = try #require(origin("https://API.Example.com./v1"))
        #expect(saved.storedValue == "https://api.example.com:443")
        #expect(CredentialOrigin(storedValue: saved.storedValue) == saved)
        let local = try #require(origin("http://[::1]/v1"))
        #expect(local.storedValue == "http://[::1]:80")
        #expect(CredentialOrigin(storedValue: local.storedValue) == local)
        #expect(CredentialOrigin(storedValue: "") == nil)
        #expect(CredentialOrigin(storedValue: "https://api.example.com") == nil, "a stored value always carries its port")
        #expect(CredentialOrigin(storedValue: "https://user@api.example.com:443") == nil)
        #expect(CredentialOrigin(storedValue: "http://example.com:80") == nil)
        #expect(CredentialOrigin(storedValue: "https://api.example.com:443/extra") == nil)
    }

    // MARK: The binding between a key and its address

    @Test func aKeyIsSentOnlyWhenTheRequestOriginMatchesTheBoundOne() {
        let bound = "https://api.example.com:443"
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: bound, requestURL: url("https://api.example.com/v1/chat/completions")) == .ready)
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: bound, requestURL: url("https://api.example.com/v1/models")) == "sk-1")
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: bound, requestURL: url("https://evil.example/v1")) == nil)
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: bound, requestURL: url("https://evil.example/v1")) == .needsReentry)
    }

    @Test func aKeyWithNoBoundOriginIsNeverSent() {
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: nil, requestURL: url("https://api.example.com/v1")) == nil)
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: nil, requestURL: url("https://api.example.com/v1")) == .needsReentry,
                "keys saved before binding existed must be entered again")
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: "garbage", requestURL: url("https://api.example.com/v1")) == .needsReentry)
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: "", requestURL: url("https://api.example.com/v1")) == .needsReentry)
    }

    @Test func noKeyMeansNothingToSendAndNothingToReenter() {
        #expect(CredentialBinding.state(secret: nil, boundOrigin: nil, requestURL: url("https://api.example.com/v1")) == .absent)
        #expect(CredentialBinding.state(secret: "", boundOrigin: "https://api.example.com:443", requestURL: url("https://api.example.com/v1")) == .absent)
        #expect(CredentialBinding.credential(secret: nil, boundOrigin: "https://api.example.com:443", requestURL: url("https://api.example.com/v1")) == nil)
    }

    @Test func noRequestAddressMeansNothingIsSent() {
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: "https://api.example.com:443", requestURL: nil) == nil)
        #expect(CredentialBinding.state(secret: "sk-1", boundOrigin: "https://api.example.com:443", requestURL: nil) == .needsReentry)
    }

    @Test func aRedirectedAddressOrAnInsecureOneNeverMatches() {
        let bound = "https://api.example.com:443"
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: bound, requestURL: url("http://api.example.com/v1")) == nil)
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: bound, requestURL: url("https://api.example.com.evil.example/v1")) == nil)
        #expect(CredentialBinding.credential(secret: "sk-1", boundOrigin: bound, requestURL: url("https://user@api.example.com/v1")) == nil)
    }

    @Test func theStateNeverPrintsTheSecret() {
        let text = "\(CredentialBinding.state(secret: "sk-very-secret", boundOrigin: nil, requestURL: nil))"
        #expect(!text.contains("sk-very-secret"))
    }

    // MARK: The custom model endpoint

    @Test func theCustomEndpointKeyFollowsItsChatAddress() {
        let saved = AnyLLMConfig(baseURL: "https://api.example.com/v1", model: "m")
        let bound = AnyLLMConfig.boundOrigin(for: saved)
        #expect(bound == "https://api.example.com:443")
        #expect(AnyLLMConfig.credential(secret: "sk-1", boundOrigin: bound, config: saved) == "sk-1")
        // A defaults write that points the same key at another host.
        let redirected = AnyLLMConfig(baseURL: "https://collect.example.net/v1", model: "m")
        #expect(AnyLLMConfig.credential(secret: "sk-1", boundOrigin: bound, config: redirected) == nil)
        #expect(AnyLLMConfig.credentialState(secret: "sk-1", boundOrigin: bound, config: redirected) == .needsReentry)
        // The same host on another port or scheme is another origin too.
        #expect(AnyLLMConfig.credential(secret: "sk-1", boundOrigin: bound, config: AnyLLMConfig(baseURL: "https://api.example.com:8443/v1", model: "m")) == nil)
    }

    @Test func aDraftWithNoUsableAddressCannotBindAKey() {
        #expect(AnyLLMConfig.boundOrigin(for: AnyLLMConfig(baseURL: "", model: "m")) == nil)
        #expect(AnyLLMConfig.boundOrigin(for: AnyLLMConfig(baseURL: "http://10.0.0.5/v1", model: "m")) == nil)
        #expect(AnyLLMConfig.boundOrigin(for: AnyLLMConfig(baseURL: "https://user:pw@api.example.com/v1", model: "m")) == nil)
        #expect(AnyLLMConfig.boundOrigin(for: AnyLLMConfig(baseURL: "http://localhost:11434/v1", model: "m")) == "http://localhost:11434")
    }

    @Test func theAccountNamesDoNotCollide() {
        #expect(AnyLLMConfig.keyAccount != AnyLLMConfig.originAccount)
        #expect(AnyLLMConfig.originAccount.hasPrefix(AnyLLMConfig.keyAccount))
    }
}
