import Foundation

/// Server-sent events from an OpenAI-compatible chat completion (`stream: true`).
public enum OpenAICompat {
    public enum Piece: Equatable, Sendable {
        case delta(String)
        case done
        case failure(String)
    }

    /// One chunk, which may hold several lines and a partial event is not assumed: callers pass complete lines.
    public static func parse(chunk: String) -> [Piece] {
        var pieces: [Piece] = []
        for raw in chunk.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(":") { continue }
            if !line.hasPrefix("data:") {
                if let message = errorMessage(in: line) { pieces.append(.failure(message)) }
                continue
            }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                pieces.append(.done)
                continue
            }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let message = errorMessage(json: json) {
                pieces.append(.failure(message))
                continue
            }
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                pieces.append(.delta(content))
            }
        }
        return pieces
    }

    public static func body(model: String, prompt: String, system: String? = nil, keepAlive: String? = nil, maxTokens: Int = 512) -> [String: Any] {
        var messages: [[String: String]] = []
        if let system, !system.isEmpty { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true, "max_tokens": maxTokens]
        if let keepAlive { body["keep_alive"] = keepAlive }
        return body
    }

    private static func errorMessage(in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return errorMessage(json: json)
    }

    private static func errorMessage(json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = json["error"] as? String, !message.isEmpty { return message }
        return nil
    }
}
