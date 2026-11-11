import Foundation
import ZeusCore

enum OpenAITTSVoice {
    static func config(defaults: UserDefaults = .standard, streaming: Bool = false) -> OpenAITTSRequest.Config? {
        guard let key = Keychain.get("openai-tts.api-key"), !key.isEmpty else { return nil }
        let baseString = defaults.string(forKey: "voice.openai.baseURL") ?? "https://api.openai.com/v1"
        guard let base = URL(string: baseString) else { return nil }
        let model = defaults.string(forKey: "voice.openai.model") ?? UltronCloudVoice.openAIModel
        let voice = defaults.string(forKey: "voice.openai.voice") ?? UltronCloudVoice.openAIVoice
        // Raw 24 kHz PCM can start playing while it downloads. Only OpenAI itself is known to offer it.
        let rawPCM = streaming && base.host == "api.openai.com"
        return OpenAITTSRequest.Config(baseURL: base, model: model, voice: voice, apiKey: key,
                                       instructions: UltronCloudVoice.openAIInstructions,
                                       responseFormat: rawPCM ? "pcm" : "wav")
    }

    static var isConfigured: Bool { config() != nil }

    /// The request for a streaming reply, with whether its body is raw PCM (else a WAV file).
    static func streamingRequest(_ text: String) -> (request: URLRequest, rawPCM: Bool, voice: String)? {
        guard let config = config(streaming: true),
              let request = OpenAITTSRequest.makeRequest(text: text, config: config, timeout: 15) else { return nil }
        return (request, config.responseFormat == "pcm", config.voice)
    }

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
