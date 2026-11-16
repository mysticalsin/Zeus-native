import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Voice restore (George + offline Kokoro)")
struct VoiceRestoreTests {
    @Test func georgeIsTheDefaultElevenLabsVoice() {
        #expect(ElevenLabsVoice.defaultVoiceID == "JBFqnCBsd6RMkjVDRZzb")
        #expect(ElevenLabsVoice.model == "eleven_flash_v2_5")
    }

    @Test func ultronDeliveryIsTakeCSettings() throws {
        let ultron = ElevenLabsVoice.voiceSettings(for: .ultron)
        #expect(ultron["stability"] as? Double == 0.6)
        #expect(ultron["similarity_boost"] as? Double == 0.85)
        #expect(ultron["style"] as? Double == 0.3)
        #expect(ultron["use_speaker_boost"] as? Bool == true)
        #expect(ultron["speed"] as? Double == 1.0)
        let body = ElevenLabsVoice.speechBody(text: "Ready.", personality: .ultron)
        #expect(body["model_id"] as? String == "eleven_flash_v2_5")
    }

    @Test func plainDeliveryIsUnchangedAndStudioDeliversUltronItsOwnSettings() {
        let plain = ElevenLabsVoice.voiceSettings(for: .plain)
        #expect(plain["stability"] as? Double == 0.45)
        #expect(plain["similarity_boost"] as? Double == 0.8)
        #expect(plain["style"] as? Double == 0.0)
        // Delivery depends on the personality only, so Studio (`speechBody` with the Studio model) keeps it too.
        let studioBody = ElevenLabsVoice.speechBody(text: "Ready.", personality: .ultron, model: ElevenLabsQuality.studioModel)
        #expect(studioBody["model_id"] as? String == "eleven_multilingual_v2")
        let studio = studioBody["voice_settings"] as? [String: Any] ?? [:]
        #expect(studio["stability"] as? Double == 0.6)
        #expect(studio["speed"] as? Double == 1.0)
        #expect(studio["use_speaker_boost"] as? Bool == true)
    }

    @Test func offlineFallbackIsKokoroMichael() {
        #expect(ElevenLabsVoice.offlineKokoroVoice == "am_michael")
        #expect(ElevenLabsVoice.offlineKokoroSpeed == 0.88)
    }

    @Test func directRequestUsesGeorgeWhenNoSavedVoice() {
        let voice = ElevenLabsVoice(route: .direct(apiKey: "test-key"), voiceID: nil)
        let request = voice.request(for: "Hello")
        #expect(request.url?.path.contains(ElevenLabsVoice.defaultVoiceID) == true)
    }

    @Test func keyRejectionsMapToSettingsAndLogDetail() {
        let body = Data(#"{"detail":{"status":"invalid_api_key","message":"nope"}}"#.utf8)
        #expect(ElevenLabsVoice.isKeyRejection(401))
        #expect(ElevenLabsVoice.isKeyRejection(402))
        #expect(ElevenLabsVoice.isKeyRejection(429))
        #expect(!ElevenLabsVoice.isKeyRejection(500))
        #expect(ElevenLabsVoice.detailStatus(from: body) == "invalid_api_key")
        #expect(ElevenLabsVoice.settingsMessage(status: 401, body: body).contains("Paste a new key"))
        let limited = Data(#"{"detail":{"status":"too_many_concurrent_requests"}}"#.utf8)
        #expect(ElevenLabsVoice.settingsMessage(status: 429, body: limited).contains("rate limit"))
        #expect(ElevenLabsVoice.settingsMessage(status: 429, body: limited).contains("offline voice"))
    }

    @Test @MainActor func settingsStoresRejectionLine() {
        let body = Data(#"{"detail":{"status":"invalid_api_key"}}"#.utf8)
        VoiceSettings.shared.noteElevenLabsKeyRejected(status: 401, body: body)
        #expect(VoiceSettings.shared.elevenLabsStatusMessage?.contains("Paste a new key") == true)
        VoiceSettings.shared.clearElevenLabsPause()
    }

    // QA7 round 11: every reply re-tried a persistently rejected ElevenLabs key because the old
    // 60 s in-memory pause on `Speaker` routinely expired between one slow fallback-brain reply
    // and the next. A 401/402 (the key itself is bad) now pauses for 15 minutes; a 429 (a real,
    // momentary rate limit) still only pauses for about a minute.
    @Test @MainActor func a401PausesForFifteenMinutes() {
        let before = Date()
        VoiceSettings.shared.noteElevenLabsKeyRejected(status: 401, body: Data())
        let until = VoiceSettings.shared.elevenLabsPausedUntil
        #expect(until != nil)
        #expect(until!.timeIntervalSince(before) > 14 * 60)
        VoiceSettings.shared.clearElevenLabsPause()
    }

    @Test @MainActor func a429PausesForAboutAMinuteNotFifteen() {
        let before = Date()
        VoiceSettings.shared.noteElevenLabsKeyRejected(status: 429, body: Data())
        let until = VoiceSettings.shared.elevenLabsPausedUntil
        #expect(until != nil)
        let delta = until!.timeIntervalSince(before)
        #expect(delta <= 90)
        VoiceSettings.shared.clearElevenLabsPause()
    }

    @Test @MainActor func clearingThePauseRemovesItAndTheMessage() {
        VoiceSettings.shared.noteElevenLabsKeyRejected(status: 401, body: Data())
        #expect(VoiceSettings.shared.elevenLabsPausedUntil != nil)
        VoiceSettings.shared.clearElevenLabsPause()
        #expect(VoiceSettings.shared.elevenLabsPausedUntil == nil)
        #expect(VoiceSettings.shared.elevenLabsStatusMessage == nil)
    }
}
