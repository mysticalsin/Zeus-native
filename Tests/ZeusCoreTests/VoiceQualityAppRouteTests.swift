import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ZeusCore

/// Opt-in is explicit. A migrated or legacy provider value is not consent.
@Suite("Voice quality app route", .serialized)
struct VoiceQualityAppRouteTests {
    private let elevenKey = "route-eleven-key-9911"
    private let googleKey = "route-google-key-9911"

    @Test func aMigratedProviderIsNotConsent() {
        let eleven = defaults("migrated-eleven")
        eleven.set(VoiceTTSProvider.elevenLabs.rawValue, forKey: VoiceProviderPreferences.selectionKey)
        eleven.set(VoiceQualityPreset.elevenLabsStudio.rawValue, forKey: VoiceQualityOptIn.presetKey)
        #expect(VoiceQualityOptIn.selection(defaults: eleven) == .synthetic)
        #expect(VoiceQualityOptIn.activeVoiceID(defaults: eleven) == "zeus.synthetic")
        #expect(VoiceSpeakAllowlist.destination(defaults: eleven) == .synthetic)

        let google = defaults("migrated-google")
        google.set(VoiceTTSProvider.googleCloud.rawValue, forKey: VoiceProviderPreferences.selectionKey)
        google.set(VoiceQualityPreset.googleNeural2.rawValue, forKey: VoiceQualityOptIn.presetKey)
        #expect(VoiceQualityOptIn.selection(defaults: google) == .synthetic)
        #expect(VoiceSpeakAllowlist.destination(defaults: google) == .synthetic)
    }

    @Test func aLegacyDomainIsNotConsent() {
        let legacy = [
            "elevenlabs",
            "ElevenLabs",
            "com.zeus.elevenlabs",
            "elevenlabs.api-key",
            "google",
            "google-cloud-tts",
            "google-cloud-tts.api-key",
            "com.zeus.app",
        ]
        for (index, raw) in legacy.enumerated() {
            let box = defaults("legacy-\(index)")
            box.set(raw, forKey: VoiceProviderPreferences.selectionKey)
            let preset: VoiceQualityPreset = raw.lowercased().contains("google") ? .googleNeural2 : .elevenLabsStudio
            box.set(preset.rawValue, forKey: VoiceQualityOptIn.presetKey)
            box.set(true, forKey: VoiceQualityOptIn.consentKey)
            #expect(VoiceQualityOptIn.selection(defaults: box) == .synthetic)
            #expect(VoiceSpeakAllowlist.destination(defaults: box) == .synthetic)
        }
    }

    @Test func choosingAPresetWritesAndReadsTheOptIn() async throws {
        let box = defaults("explicit-eleven")
        VoiceQualityOptIn.set(.elevenLabsFast, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .preset(.elevenLabsFast))
        #expect(VoiceSpeakAllowlist.destination(defaults: box) == .quality(.elevenLabsFast))
        #expect(box.string(forKey: VoiceProviderPreferences.selectionKey) == VoiceTTSProvider.elevenLabs.rawValue)

        QualityURLStub.reset(reply: .init(status: 200, body: Data([0x49, 0x44, 0x33, 0x04])))
        let speaker = VoiceQualitySpeaker(
            meter: try VoiceQualityMeter(directory: try temporaryDirectory()),
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2)
        )
        let synthesis = speaker.synthesizeIfEnabled(
            text: "Hello",
            defaults: box,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: elevenKey])
        )
        let error = await firstError(synthesis)
        #expect(error == nil)
        #expect(QualityURLStub.requests.map { $0.url?.host } == ["api.elevenlabs.io"])

        VoiceQualityOptIn.set(.googleNeural2, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .preset(.googleNeural2))
        let audio = Data([0x49, 0x44, 0x33, 0x04])
        let body = try JSONSerialization.data(withJSONObject: ["audioContent": audio.base64EncodedString()])
        QualityURLStub.reset(reply: .init(status: 200, body: body))
        let google = speaker.synthesizeIfEnabled(
            text: "Hello",
            defaults: box,
            credential: ProviderCredential(fields: [ProviderCredentialLocation.account: googleKey])
        )
        #expect(await firstError(google) == nil)
        #expect(QualityURLStub.requests.map { $0.url?.host } == ["texttospeech.googleapis.com"])

        VoiceQualityOptIn.set(nil, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .synthetic)
        #expect(VoiceSpeakAllowlist.destination(defaults: box) == .synthetic)
        #expect(VoiceQualityOptIn.activeVoiceID(defaults: box) == "zeus.synthetic")
    }

    @Test func thePickerWritesOnePresetAndClearsItForLocal() {
        let box = defaults("picker")
        VoiceQualityOptIn.applyPicker(providerID: ElevenLabsTTSAdapter.id, preset: .elevenLabsStudio, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .preset(.elevenLabsStudio))
        VoiceQualityOptIn.applyPicker(providerID: GoogleCloudTTSAdapter.id, preset: .googleWavenet, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .preset(.googleWavenet))
        VoiceQualityOptIn.applyPicker(providerID: VoiceProviderChoice.localID, preset: .elevenLabsFast, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .synthetic)
        VoiceQualityOptIn.applyPicker(providerID: ElevenLabsTTSAdapter.id, preset: .googleNeural2, defaults: box)
        #expect(VoiceQualityOptIn.selection(defaults: box) == .synthetic)
    }

    @Test func aRejectedKeyNamesWhatToDoAndOmitsTheKey() async {
        let sentinel = "paste-sentinel-77aa"
        let session = VoiceProviderSession(
            store: MemoryCredentialStore(),
            transport: URLSessionProviderTransport(protocolClasses: [QualityURLStub.self], timeout: 2),
            local: QuietLocal(),
            preferences: VoiceProviderPreferences(defaults: defaults("key-copy"))
        )
        await session.saveKey(providerID: ElevenLabsTTSAdapter.id, key: "bad\n\(sentinel)")
        let line = await session.card().statusLine
        #expect(line == VoiceProviderKeyCopy.rejected)
        #expect(!line.contains(sentinel))
        #expect(!line.contains("\n"))
        #expect(line.contains("Paste"))
    }

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "voice-quality-app-\(name)-\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        box.removePersistentDomain(forName: suite)
        return box
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-quality-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func firstError(_ synthesis: Synthesis) async -> Error? {
        do {
            for try await _ in synthesis.chunks {}
            return nil
        } catch { return error }
    }
}

private struct QuietLocal: LocalVoiceSpeaking {
    func speak(_ text: String) async -> Data { Data() }
}
