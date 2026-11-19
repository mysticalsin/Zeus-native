import Foundation

/// Builds the Gemini text-to-speech request and reads its reply.
///
/// Source (read 2026-11-16): https://ai.google.dev/gemini-api/docs/speech-generation, which redirects to
/// https://aistudio.google.com/docs/speech-generation. The current Gemini 3.8 TTS models
/// (`gemini-3.8-flash-tts`, `gemini-3.8-flash-lite-tts`) use the Interactions API:
/// `POST https://generativelanguage.googleapis.com/v1beta/interactions`, header `x-goog-api-key`,
/// `generation_config.speech_config[{voice}]`, `response_format{type:audio, mime_type:audio/l16, sample_rate:24000}`.
/// The audio comes back base64 in `steps[].content[].data` (the last audio block). The default for a unary request
/// is a WAV file, so raw 16-bit 24 kHz mono PCM is requested explicitly. Older preview models used
/// `generateContent` with `responseModalities: ["AUDIO"]`; the page lists them as superseded.
/// The reply shape of this exact call was read from the docs, not exercised with a live key here.
public enum GeminiTTSRequest {
    public static let defaultModel = "gemini-3.8-flash-lite-tts"
    public static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!
    public static let sampleRate = 24_000

    public struct Config: Sendable, Equatable {
        public var model: String
        public var voice: String
        public var apiKey: String
        public init(model: String = GeminiTTSRequest.defaultModel, voice: String = GeminiVoiceCatalog.defaultVoice, apiKey: String) {
            self.model = model
            self.voice = voice
            self.apiKey = apiKey
        }
    }

    public static func body(text: String, config: Config) -> [String: Any] {
        [
            "model": config.model,
            "input": [[
                "type": "user_input",
                "content": [["type": "text", "text": text]],
            ]],
            "response_format": ["type": "audio", "mime_type": "audio/l16", "sample_rate": sampleRate],
            "generation_config": ["speech_config": [["voice": config.voice]]],
        ]
    }

    public static func makeRequest(text: String, config: Config, timeout: TimeInterval = 30) -> URLRequest? {
        guard !config.apiKey.isEmpty, !text.isEmpty else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body(text: text, config: config))
        return request
    }

    /// A line for voice.log. It never holds the key.
    public static func logSummary(config: Config) -> String {
        "gemini model=\(config.model) voice=\(config.voice)"
    }

    /// The raw 16-bit 24 kHz mono PCM in a reply, or nil when there is no audio. A WAV reply loses its header.
    public static func pcm(fromResponse data: Data) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let steps = root["steps"] as? [[String: Any]] else { return nil }
        var last: String?
        for step in steps where step["type"] as? String == "model_output" {
            for block in step["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "audio" {
                if let encoded = block["data"] as? String { last = encoded }
            }
        }
        guard let last, let audio = Data(base64Encoded: last), !audio.isEmpty else { return nil }
        return stripWAVHeader(audio)
    }

    private static func stripWAVHeader(_ data: Data) -> Data {
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else { return data }
        var at = 12
        while at + 8 <= data.count {
            let size = Int(data[at + 4]) | Int(data[at + 5]) << 8 | Int(data[at + 6]) << 16 | Int(data[at + 7]) << 24
            if data[at..<(at + 4)] == Data("data".utf8) {
                let start = at + 8
                return data[start..<min(data.count, start + size)]
            }
            at += 8 + size + (size & 1)
        }
        return data
    }

    /// A WAV file around 24 kHz mono 16-bit PCM, so a preview can play from a temporary file.
    public static func wav(fromPCM pcm: Data) -> Data {
        func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        func le16(_ value: Int) -> [UInt8] { (0..<2).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        var header = Data("RIFF".utf8)
        header.append(contentsOf: le32(36 + pcm.count))
        header.append(Data("WAVEfmt ".utf8))
        header.append(contentsOf: le32(16) + le16(1) + le16(1) + le32(sampleRate) + le32(sampleRate * 2) + le16(2) + le16(16))
        header.append(Data("data".utf8))
        header.append(contentsOf: le32(pcm.count))
        return header + pcm
    }
}
