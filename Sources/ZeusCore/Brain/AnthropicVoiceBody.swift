import Foundation

/// The Messages API body for a spoken answer. The system prompt goes in as a content block with
/// `cache_control` so a repeated persona prefix is read from the cache (a prefix below the model's minimum
/// cacheable size simply is not cached). `lean` also turns thinking off and sets low effort for the fast tier:
/// a voice answer must start streaming at once. If the API rejects those fields the caller retries with
/// `lean: false`.
public enum AnthropicVoiceBody {
    public static func make(model: String, system: String, messages: [[String: String]], maxTokens: Int, lean: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "messages": messages,
        ]
        if lean {
            body["thinking"] = ["type": "disabled"]
            body["output_config"] = ["effort": "low"]
        }
        return body
    }

    /// The fast tier's tries, in order: the current Haiku lean, the same model plain, then the previous Haiku.
    public static func fastAttempts(current: String, fallback: String = "claude-haiku-4-5") -> [(model: String, lean: Bool)] {
        [(current, true), (current, false), (fallback, false)]
    }

    /// Only a rejected request body or an unknown model is retried; auth, quota and server errors are not.
    public static func shouldRetry(status: Int) -> Bool { status == 400 || status == 404 }
}
