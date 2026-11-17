import Foundation
import ZeusCore

/// Google Gemini text to speech with the owner's own AI Studio key (Keychain account `gemini-tts.api-key`).
/// The request and reply shapes live in `GeminiTTSRequest`. The key is never logged.
enum GeminiTTSVoice {
    static func config(defaults: UserDefaults = .standard) -> GeminiTTSRequest.Config? {
        guard let key = Keychain.get("gemini-tts.api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        let model = defaults.string(forKey: "voice.gemini.model").flatMap { $0.isEmpty ? nil : $0 } ?? GeminiTTSRequest.defaultModel
        let voice = GeminiVoiceCatalog.resolve(stored: defaults.string(forKey: "voice.gemini.voice"))
        return GeminiTTSRequest.Config(model: model, voice: voice, apiKey: key)
    }

    static var isConfigured: Bool { config() != nil }

    /// Raw 24 kHz 16-bit mono PCM for `text`, or nil on any failure. `voice` overrides the saved one (previews).
    static func renderPCM(_ text: String, voice: String? = nil, session: URLSession = .shared) async -> Data? {
        guard var config = config() else { return nil }
        if let voice { config.voice = voice }
        guard let request = GeminiTTSRequest.makeRequest(text: text, config: config) else { return nil }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return GeminiTTSRequest.pcm(fromResponse: data)
        } catch {
            return nil
        }
    }

    /// Writes a WAV file in the temporary folder and returns its URL, or nil on failure.
    static func render(_ text: String, session: URLSession = .shared) async -> URL? {
        guard let pcm = await renderPCM(text, session: session) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-gemini-tts-\(UUID().uuidString).wav")
        do {
            try GeminiTTSRequest.wav(fromPCM: pcm).write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
