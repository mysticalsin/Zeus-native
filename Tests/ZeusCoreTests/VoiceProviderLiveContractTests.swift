import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
@Suite("Live voice provider contracts", .serialized)
struct VoiceProviderLiveContractTests {
    @Test(.disabled(if: VoiceProviderLiveGate.shouldSkip("ZEUS_LIVE_ELEVENLABS_KEY"), "ZEUS_LIVE_ELEVENLABS_KEY is not set"))
    func elevenLabsListsVoicesAndReturnsAudio() async throws {
        let key = try liveKey("ZEUS_LIVE_ELEVENLABS_KEY")
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

    @Test(.disabled(if: VoiceProviderLiveGate.shouldSkip("ZEUS_LIVE_GOOGLE_TTS_KEY"), "ZEUS_LIVE_GOOGLE_TTS_KEY is not set"))
    func googleCloudListsVoicesAndReturnsAudio() async throws {
        let key = try liveKey("ZEUS_LIVE_GOOGLE_TTS_KEY")
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

    @Test func aMissingLiveKeyIsCountedAsASkip() {
        VoiceProviderLiveGate.resetSkips()
        #expect(VoiceProviderLiveGate.decision(nil, name: "ZEUS_LIVE_ELEVENLABS_KEY") == .skip("ZEUS_LIVE_ELEVENLABS_KEY"))
        #expect(VoiceProviderLiveGate.decision("  \n", name: "ZEUS_LIVE_GOOGLE_TTS_KEY") == .skip("ZEUS_LIVE_GOOGLE_TTS_KEY"))
        #expect(VoiceProviderLiveGate.decision("present-key", name: "ZEUS_LIVE_ELEVENLABS_KEY") == .run("present-key"))
        VoiceProviderLiveGate.noteSkip("ZEUS_LIVE_ELEVENLABS_KEY")
        VoiceProviderLiveGate.noteSkip("ZEUS_LIVE_GOOGLE_TTS_KEY")
        #expect(VoiceProviderLiveGate.skipCount == 2)
        #expect(VoiceProviderLiveGate.skipped == ["ZEUS_LIVE_ELEVENLABS_KEY", "ZEUS_LIVE_GOOGLE_TTS_KEY"])
    }

    private func liveKey(_ name: String) throws -> String {
        switch VoiceProviderLiveGate.decision(ProcessInfo.processInfo.environment[name], name: name) {
        case .skip:
            #expect(Bool(false), "\(name) is not set")
            throw LiveKeyMissing(name: name)
        case .run(let key):
            return key
        }
    }
}

private struct LiveKeyMissing: Error {
    var name: String
}

enum VoiceProviderLiveGate {
    enum Decision: Equatable {
        case skip(String)
        case run(String)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String] = []

    static var skipCount: Int { lock.lock(); defer { lock.unlock() }; return names.count }
    static var skipped: [String] { lock.lock(); defer { lock.unlock() }; return names }

    static func resetSkips() {
        lock.lock(); names = []; lock.unlock()
    }

    static func noteSkip(_ name: String) {
        lock.lock(); names.append(name); lock.unlock()
    }

    static func shouldSkip(_ name: String) -> Bool {
        if case .skip(let skipped) = decision(ProcessInfo.processInfo.environment[name], name: name) {
            noteSkip(skipped)
            return true
        }
        return false
    }

    static func decision(_ raw: String?, name: String) -> Decision {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .skip(name) }
        return .run(trimmed)
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
