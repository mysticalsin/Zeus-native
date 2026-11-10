import Foundation

/// 16 kHz mono Float samples as 16-bit little-endian PCM, the format both cloud APIs take.
public enum PCM16 {
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample.isFinite ? sample : 0))
            let value = Int16((clamped * Float(Int16.max)).rounded())
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// A complete WAV file (RIFF header plus PCM) for upload.
    public static func wav(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        let pcm = encode(samples)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))           // fmt chunk size
        append(UInt16(1))            // PCM
        append(UInt16(1))            // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)) // byte rate
        append(UInt16(2))            // block align
        append(UInt16(16))           // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

/// Settings > Dictation > Vocabulary: what Save writes when words were learned (History's Add to
/// Vocabulary) after the text boxes were filled. The person's edits win; entries added elsewhere since
/// the boxes were loaded are kept instead of being silently dropped.
public enum VocabularyMerge {
    public static func merged(edited: Vocabulary, loaded: Vocabulary, current: Vocabulary) -> Vocabulary {
        let loadedWords = Set(loaded.words.map { $0.lowercased() })
        var seenWords = Set(edited.words.map { $0.lowercased() })
        var words = edited.words
        for word in current.words where !loadedWords.contains(word.lowercased()) && seenWords.insert(word.lowercased()).inserted {
            words.append(word)
        }
        let loadedKeys = Set(loaded.replacements.map { $0.original.lowercased() })
        var seenKeys = Set(edited.replacements.map { $0.original.lowercased() })
        var replacements = edited.replacements
        for rule in current.replacements where !loadedKeys.contains(rule.original.lowercased()) && seenKeys.insert(rule.original.lowercased()).inserted {
            replacements.append(rule)
        }
        return Vocabulary(words: words, replacements: replacements)
    }
}

/// One-line, key-free errors for the cloud engines.
public enum CloudTranscriptionError: LocalizedError, Equatable, Sendable {
    case missingKey(String)
    case rejectedKey(String)
    case quota(String)
    case server(String, String)
    case network(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let provider): "\(provider) needs your API key. Add it in Settings \u{203A} Murmure."
        case .rejectedKey(let provider): "\(provider) did not accept the API key. Check it in Settings."
        case .quota(let provider): "\(provider) quota or rate limit reached. Try again later or pick another engine."
        case .server(let provider, let message): "\(provider): \(message)"
        case .network(let provider): "\(provider) could not be reached. Check your connection."
        case .timeout(let provider): "\(provider) took too long to answer."
        }
    }

    /// The first line of a server message, shortened so it fits a toast or a settings row.
    static func oneLine(_ message: String, limit: Int = 140) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "\u{2026}" : trimmed
    }
}

/// OpenAI's file transcription: one request after the person stops talking.
/// Docs: https://developers.openai.com/api/docs/guides/speech-to-text (gpt-transcribe, the
/// successor of gpt-4o-transcribe, which retires on 26 February 2027).
public enum OpenAITranscription {
    public static let provider = "OpenAI"
    public static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public static let model = "gpt-transcribe"

    public static func request(wav: Data, apiKey: String, prompt: String, keywords: [String], language: String?,
                               boundary: String = "zeus-\(UUID().uuidString)") -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        if !prompt.isEmpty { field("prompt", prompt) }
        for keyword in DictationVocabularyPrompt.cloudKeywords(keywords) { field("keywords[]", keyword) }
        if let code = DictationLanguage.engineLanguageCode(for: language) {
            // gpt-transcribe takes the chosen language as `languages[]`, so the choice is never auto-detected.
            field("languages[]", code)
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    private struct Success: Decodable { let text: String }
    private struct Failure: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }

    public static func parse(data: Data, status: Int) throws -> String {
        switch status {
        case 200..<300:
            guard let success = try? JSONDecoder().decode(Success.self, from: data) else {
                throw CloudTranscriptionError.server(provider, "Unexpected answer.")
            }
            return success.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case 401, 403: throw CloudTranscriptionError.rejectedKey(provider)
        case 429: throw CloudTranscriptionError.quota(provider)
        default:
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error?.message ?? "HTTP \(status)"
            throw CloudTranscriptionError.server(provider, CloudTranscriptionError.oneLine(message))
        }
    }
}

/// ElevenLabs Scribe v2 Realtime over a WebSocket: audio streams while the person speaks and a
/// manual commit at the end returns the final text.
/// Docs: https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime
public enum ElevenLabsRealtime {
    public static let provider = "ElevenLabs"
    public static let model = "scribe_v2_realtime"
    /// 250 ms of 16 kHz 16-bit audio per message.
    public static let chunkBytes = 8_000

    public static func url(language: String?, keyterms: [String]) -> URL {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: model),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
        ]
        if let code = DictationLanguage.engineLanguageCode(for: language) { items.append(URLQueryItem(name: "language_code", value: code)) }
        items += DictationVocabularyPrompt.cloudKeywords(keyterms).map { URLQueryItem(name: "keyterms", value: $0) }
        components.queryItems = items
        return components.url!
    }

    public static func request(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    /// One `input_audio_chunk` message. An empty chunk with `commit` ends the segment.
    public static func audioChunk(_ pcm: Data, commit: Bool, sampleRate: Int = 16_000) -> String {
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm.base64EncodedString(),
            "commit": commit,
            "sample_rate": sampleRate,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public enum Event: Equatable, Sendable {
        case started(sessionID: String)
        case partial(String)
        case committed(String)
        case warning(String)
        case failure(type: String, message: String)
        case other(String)
    }

    static let errorTypes: Set<String> = [
        "error", "auth_error", "quota_exceeded", "commit_throttled", "unaccepted_terms", "rate_limited",
        "queue_overflow", "resource_exhausted", "session_time_limit_exceeded", "input_error", "invalid_request",
        "chunk_size_exceeded", "insufficient_audio_activity", "transcriber_error",
    ]

    public static func parse(_ message: String) -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
              let type = object["message_type"] as? String else { return .other("unreadable") }
        switch type {
        case "session_started": return .started(sessionID: object["session_id"] as? String ?? "")
        case "partial_transcript": return .partial(object["text"] as? String ?? "")
        case "committed_transcript", "committed_transcript_with_timestamps": return .committed(object["text"] as? String ?? "")
        case "warning": return .warning(object["warning"] as? String ?? "")
        case let type where errorTypes.contains(type): return .failure(type: type, message: object["error"] as? String ?? type)
        default: return .other(type)
        }
    }

    public static func error(type: String, message: String) -> CloudTranscriptionError {
        switch type {
        case "auth_error": .rejectedKey(provider)
        case "quota_exceeded", "rate_limited", "commit_throttled": .quota(provider)
        case "unaccepted_terms": .server(provider, "Accept the speech-to-text terms on elevenlabs.io first.")
        default: .server(provider, CloudTranscriptionError.oneLine(message))
        }
    }
}

/// The text of a realtime session so far: committed segments in order, then the live partial.
public struct RealtimeTranscript: Equatable, Sendable {
    public private(set) var committed: [String] = []
    public private(set) var partial = ""

    public init() {}

    public mutating func apply(_ event: ElevenLabsRealtime.Event) {
        switch event {
        case .partial(let text): partial = text
        case .committed(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { committed.append(trimmed) }
            partial = ""
        default: break
        }
    }

    /// Everything heard, the partial included (for when the final commit never comes).
    public var text: String {
        (committed + [partial.trimmingCharacters(in: .whitespacesAndNewlines)]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
