import Foundation
import ZeusCore

enum OpenAITTSVoice {
    static func config(defaults: UserDefaults = .standard) -> OpenAITTSRequest.Config? {
        guard let key = Keychain.get("openai-tts.api-key"), !key.isEmpty else { return nil }
        let baseString = defaults.string(forKey: "voice.openai.baseURL") ?? "https://api.openai.com/v1"
        guard let base = URL(string: baseString) else { return nil }
        let model = defaults.string(forKey: "voice.openai.model") ?? "tts-1"
        let voice = defaults.string(forKey: "voice.openai.voice") ?? "alloy"
        return OpenAITTSRequest.Config(baseURL: base, model: model, voice: voice, apiKey: key)
    }

    static var isConfigured: Bool { config() != nil }

    /// Writes a WAV file and returns its URL, or nil on failure.
    static func render(_ text: String, session: URLSession = .shared) async -> URL? {
        guard let config = config(), let request = OpenAITTSRequest.makeRequest(text: text, config: config) else { return nil }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("zeus-openai-tts-\(UUID().uuidString).wav")
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
