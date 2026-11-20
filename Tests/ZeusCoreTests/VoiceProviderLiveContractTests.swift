import Foundation
import Testing
@testable import ZeusCore

/// Opt-in contract against the real voice APIs. It does not run in CI.
///
/// The key is read from the environment and is never printed, logged, or written into an assertion message.
/// A missing or empty variable skips that provider. No other suite uses this skip.
///
/// ```sh
/// ZEUS_LIVE_ELEVENLABS_KEY='…' swift test --filter VoiceProviderLiveContractTests/elevenLabs
/// ZEUS_LIVE_GOOGLE_TTS_KEY='…' swift test --filter VoiceProviderLiveContractTests/googleCloud
/// ```
///
/// Run both by exporting either variable and filtering on `VoiceProviderLiveContractTests`.
/// Native playback of the returned bytes is MAC-PENDING. This test only checks that the service
/// accepted the key, listed voices, and returned audio bytes.
@Suite("Live voice provider contracts")
struct VoiceProviderLiveContractTests {
    @Test(.enabled(if: VoiceProviderLiveGate.elevenLabs != nil))
    func elevenLabsListsVoicesAndReturnsAudio() async throws {
        let key = try #require(VoiceProviderLiveGate.elevenLabs)
        let log = LiveLog()
        let transport = URLSessionProviderTransport(timeout: ProviderHTTPBudget.requestTimeout, log: ProviderLog { log.append($0) })
        let adapter = ElevenLabsTTSAdapter()
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: key])
        try await adapter.validate(credential: credential, using: transport)
        let voices = try await adapter.listVoices(credential: credential, using: transport)
        let voice = try #require(voices.first)
        let synthesis = try #require(adapter.synthesize(text: "Hello from Zeus.", voice: voice, credential: credential, using: transport))
        var audio = Data()
        for try await chunk in synthesis.chunks { audio.append(chunk.data) }
        #expect(!voices.isEmpty)
        #expect(audio.count > 32)
        #expect(!log.leaked(key))
    }

    @Test(.enabled(if: VoiceProviderLiveGate.google != nil))
    func googleCloudListsVoicesAndReturnsAudio() async throws {
        let key = try #require(VoiceProviderLiveGate.google)
        let log = LiveLog()
        let transport = URLSessionProviderTransport(timeout: ProviderHTTPBudget.requestTimeout, log: ProviderLog { log.append($0) })
        let adapter = GoogleCloudTTSAdapter()
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: key])
        try await adapter.validate(credential: credential, using: transport)
        let voices = try await adapter.listVoices(credential: credential, using: transport)
        let voice = try #require(voices.first { $0.language == "en-US" } ?? voices.first)
        let synthesis = try #require(adapter.synthesize(text: "Hello from Zeus.", voice: voice, credential: credential, using: transport))
        var audio = Data()
        for try await chunk in synthesis.chunks { audio.append(chunk.data) }
        #expect(!voices.isEmpty)
        #expect(audio.count > 32)
        #expect(!log.leaked(key))
    }
}

enum VoiceProviderLiveGate {
    static var elevenLabs: String? { value("ZEUS_LIVE_ELEVENLABS_KEY") }
    static var google: String? { value("ZEUS_LIVE_GOOGLE_TTS_KEY") }

    private static func value(_ name: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[name] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class LiveLog: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ line: String) { lock.lock(); text += line + "\n"; lock.unlock() }
    func leaked(_ secret: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return text.contains(secret)
    }
}
