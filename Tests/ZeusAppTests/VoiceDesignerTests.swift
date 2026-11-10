import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// No network and no Keychain: requests are built with a dummy key and parsed from fixtures shaped
/// like the ElevenLabs API reference (text-to-voice/design and text-to-voice).
@Suite("ElevenLabs voice design")
struct VoiceDesignerTests {
    private func json(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func designRequestMatchesTheDocs() throws {
        let request = VoiceDesigner.designRequest(apiKey: "test-key")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-voice/design?output_format=mp3_44100_128")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try json(request)
        #expect(body["model_id"] as? String == "eleven_multilingual_ttv_v2")
        #expect(body["voice_description"] as? String == VoiceDesigner.voiceDescription)
        #expect(body["text"] as? String == VoiceDesigner.sampleText)
        #expect(Set(body.keys) == ["model_id", "voice_description", "text"])
    }

    @Test func sampleTextAndDescriptionFitTheLimits() {
        #expect(VoiceDesigner.textRange.contains(VoiceDesigner.sampleText.count))
        let description = VoiceDesigner.voiceDescription.lowercased()
        for quality in ["deep", "smooth", "measured", "american", "unhurried", "quietly amused", "synthetic sheen", "theatrical but calm"] {
            #expect(description.contains(quality), "\(quality)")
        }
        #expect(!description.contains("ultron"))
    }

    @Test func createRequestMatchesTheDocs() throws {
        let request = VoiceDesigner.createRequest(apiKey: "test-key", generatedVoiceID: "gen123", playedNotSelected: ["gen456"])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-voice")
        let body = try json(request)
        #expect(body["voice_name"] as? String == "Zeus")
        #expect(body["generated_voice_id"] as? String == "gen123")
        #expect(body["voice_description"] as? String == VoiceDesigner.voiceDescription)
        #expect(body["played_not_selected_voice_ids"] as? [String] == ["gen456"])

        let bare = try json(VoiceDesigner.createRequest(apiKey: "k", generatedVoiceID: "gen123"))
        #expect(bare["played_not_selected_voice_ids"] == nil)
    }

    @Test func parsesThePreviews() throws {
        let audio = Data("ID3 fake mp3".utf8)
        let fixture = """
        {
          "previews": [
            {"audio_base_64": "\(audio.base64EncodedString())", "generated_voice_id": "gen1", "media_type": "audio/mpeg", "duration_secs": 12.4, "language": "en"},
            {"audio_base_64": "\(audio.base64EncodedString())", "generated_voice_id": "gen2", "media_type": "audio/mpeg", "duration_secs": 11.9, "language": null},
            {"audio_base_64": "\(audio.base64EncodedString())", "generated_voice_id": "gen3", "media_type": "audio/mpeg", "duration_secs": 12.1}
          ],
          "text": "Good evening, Tony."
        }
        """
        let previews = try VoiceDesigner.parsePreviews(Data(fixture.utf8))
        #expect(previews.map(\.id) == ["gen1", "gen2", "gen3"])
        #expect(previews[0].audio == audio)
        #expect(previews[0].mediaType == "audio/mpeg")
        #expect(previews[0].duration == 12.4)
    }

    @Test func badPreviewsAreUnreadable() {
        #expect(throws: VoiceDesigner.Failure.unreadable) { try VoiceDesigner.parsePreviews(Data("{}".utf8)) }
        #expect(throws: VoiceDesigner.Failure.unreadable) { try VoiceDesigner.parsePreviews(Data(#"{"previews": [], "text": "x"}"#.utf8)) }
    }

    @Test func parsesTheCreatedVoice() throws {
        let fixture = #"{"voice_id": "abc123XYZ", "name": "Zeus", "category": "generated", "labels": {}, "description": "deep", "preview_url": null}"#
        #expect(try VoiceDesigner.parseVoiceID(Data(fixture.utf8)) == "abc123XYZ")
        #expect(throws: VoiceDesigner.Failure.unreadable) { try VoiceDesigner.parseVoiceID(Data(#"{"name": "Zeus"}"#.utf8)) }
    }

    @Test func errorsBecomeOnePlainLine() {
        func failure(_ status: Int, _ body: String) -> VoiceDesigner.Failure { VoiceDesigner.failure(status: status, body: Data(body.utf8)) }
        #expect(failure(401, #"{"detail": {"status": "invalid_api_key", "message": "Invalid API key"}}"#) == .badKey)
        #expect(failure(401, #"{"detail": {"status": "quota_exceeded", "message": "This request exceeds your quota."}}"#) == .quota)
        #expect(failure(429, #"{"detail": {"status": "too_many_concurrent_requests"}}"#) == .rateLimited)
        #expect(failure(400, #"{"detail": {"status": "voice_limit_reached", "message": "You have reached your maximum amount of custom voices"}}"#) == .voiceSlotsFull)
        #expect(failure(422, #"{"detail": [{"loc": ["body", "text"], "msg": "Text must be between 100 and 1000 characters", "type": "value_error"}]}"#)
                == .rejected("Text must be between 100 and 1000 characters"))
        #expect(failure(500, "oops") == .server(500))
        for item in [VoiceDesigner.Failure.noKey, .quota, .network, .badKey] {
            #expect(!item.message.contains("\n"))
            #expect(!item.message.isEmpty)
        }
    }

    @Test func ultronDeliveryIsMoreExpressive() throws {
        let ultron = ElevenLabsVoice.voiceSettings(for: .ultron)
        let plain = ElevenLabsVoice.voiceSettings(for: .plain)
        let ultronStability = try #require(ultron["stability"] as? Double)
        let plainStability = try #require(plain["stability"] as? Double)
        #expect(ultronStability < plainStability)
        #expect(ultronStability == 0.35)
        #expect((ultron["style"] as? Double ?? 0) == 0.3)
        #expect(ultron["use_speaker_boost"] as? Bool == true)
        #expect(ultron["speed"] as? Double == 0.95)
        let body = ElevenLabsVoice.speechBody(text: "Done.", personality: .ultron)
        #expect(body["model_id"] as? String == "eleven_flash_v2_5")
        #expect(body["text"] as? String == "Done.")
    }
}
