import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

@Suite("Voice provider fake", .serialized)
struct VoiceProviderFakeTests {
    @Test func theE2EServiceIsNotTheProductionService() {
        #expect(VoiceProviderE2E.service(for: ElevenLabsTTSAdapter.id) == "app.zeus.voice-provider.e2e.elevenlabs")
        #expect(VoiceProviderE2E.service(for: ElevenLabsTTSAdapter.id) != ProviderCredentialLocation.service(for: ElevenLabsTTSAdapter.id))
        #expect(VoiceProviderE2E.isEnabled([: ]) == false)
        #expect(VoiceProviderE2E.isEnabled([VoiceProviderE2E.environmentName: "1"]))
        #expect(VoiceProviderE2E.failsSynthesis([VoiceProviderE2E.environmentName: "fail"]))
        #expect(!VoiceProviderE2E.failsSynthesis([VoiceProviderE2E.environmentName: "1"]))
        #expect(VoiceProviderFakeAudio.wavSilence().prefix(4) == Data("RIFF".utf8))
        #expect(VoiceProviderAccounts.keyAccount(for: ElevenLabsTTSAdapter.id) == "elevenlabs.api-key")
        #expect(VoiceProviderAccounts.service == "com.zeus.app")
        #expect(VoiceProviderAccounts.choice(fromTTSProvider: "elevenLabs") == .provider(ElevenLabsTTSAdapter.id))
        #expect(VoiceProviderAccounts.choice(fromTTSProvider: "kokoro") == .local)
        #expect(VoiceProviderPreferences.selectionKey == "voice.ttsProvider")
    }

    @Test func offlineFallbackTriesTheLocalVoiceThenTheMacVoice() async {
        #expect(OfflineVoiceChain.route(localReady: true) == [.local, .systemSpeech])
        #expect(OfflineVoiceChain.route(localReady: false) == [.systemSpeech])
        #expect(!OfflineVoiceChain.route(localReady: false, systemReady: false).isEmpty)
        let localFirst = await OfflineVoicePlayback.speak(text: "hi", localReady: true, local: { _ in Data("local".utf8) }, system: { _ in Data("mac".utf8) })
        #expect(localFirst.step == .local)
        #expect(localFirst.audio == Data("local".utf8))
        let mac = await OfflineVoicePlayback.speak(text: "hi", localReady: true, local: { _ in Data() }, system: { _ in Data("mac".utf8) })
        #expect(mac.step == .systemSpeech)
        #expect(mac.audio == Data("mac".utf8))
        let neverSilent = await OfflineVoicePlayback.speak(text: "hi", localReady: false, local: { _ in Data() }, system: { _ in Data() })
        #expect(!neverSilent.audio.isEmpty)
    }

    @Test func theFakeAnswersOnlyTheDocumentedKeyAndCanFailSynthesis() async throws {
        defer { VoiceProviderFakeProtocol.failSynthesis = false }
        VoiceProviderFakeProtocol.failSynthesis = false
        let transport = URLSessionProviderTransport(protocolClasses: [VoiceProviderFakeProtocol.self], timeout: 2)
        let wrong = ProviderCredential(fields: [ProviderCredentialLocation.account: "not-the-fake-key"])
        await #expect(throws: ProviderFailure.unauthorized) {
            try await ElevenLabsTTSAdapter().validate(credential: wrong, using: transport)
        }
        let credential = ProviderCredential(fields: [ProviderCredentialLocation.account: VoiceProviderE2E.fakeKey])
        try await ElevenLabsTTSAdapter().validate(credential: credential, using: transport)
        let voices = try await ElevenLabsTTSAdapter().listVoices(credential: credential, using: transport)
        #expect(voices.first?.name == VoiceProviderE2E.voiceName)
        let synthesis = try #require(ElevenLabsTTSAdapter().synthesize(
            text: "Hello", voice: ProviderVoice(id: VoiceProviderE2E.voiceID, name: VoiceProviderE2E.voiceName, language: nil),
            credential: credential, using: transport))
        var audio = Data()
        for try await chunk in synthesis.chunks { audio.append(chunk.data) }
        #expect(audio.prefix(4) == Data("RIFF".utf8))
        #expect(audio.range(of: Data(VoiceProviderE2E.fakeKey.utf8)) == nil)

        VoiceProviderFakeProtocol.failSynthesis = true
        let failing = URLSessionProviderTransport(protocolClasses: [VoiceProviderFakeProtocol.self], timeout: 2)
        let denied = try #require(ElevenLabsTTSAdapter().synthesize(
            text: "Hello", voice: ProviderVoice(id: VoiceProviderE2E.voiceID, name: VoiceProviderE2E.voiceName, language: nil),
            credential: credential, using: failing))
        await #expect(throws: ProviderFailure.server(500)) {
            for try await _ in denied.chunks { }
        }
    }
}
