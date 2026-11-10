import Foundation

/// Builds HTTP requests for OpenAI-compatible TTS endpoints (OpenAI, Cartesia proxies, local mlx-audio).
public enum OpenAITTSRequest {
    public struct Config: Sendable, Equatable {
        public var baseURL: URL
        public var model: String
        public var voice: String
        public var apiKey: String

        public init(baseURL: URL, model: String, voice: String, apiKey: String) {
            self.baseURL = baseURL
            self.model = model
            self.voice = voice
            self.apiKey = apiKey
        }
    }

    public static func speechURL(base: URL) -> URL {
        var trimmed = base
        if trimmed.path.hasSuffix("/") { trimmed.deleteLastPathComponent() }
        if trimmed.path.hasSuffix("/v1") {
            return trimmed.appendingPathComponent("audio/speech")
        }
        return trimmed.appendingPathComponent("v1/audio/speech")
    }

    public static func body(text: String, config: Config) -> [String: Any] {
        [
            "model": config.model,
            "input": text,
            "voice": config.voice,
            "response_format": "wav",
        ]
    }

    public static func makeRequest(text: String, config: Config, timeout: TimeInterval = 30) -> URLRequest? {
        guard !config.apiKey.isEmpty, !text.isEmpty else { return nil }
        let url = speechURL(base: config.baseURL)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body(text: text, config: config))
        return request
    }
}
