import Foundation

/// Bounded Anthropic Messages SSE envelope around the strict scene NDJSON stream.
///
/// Event shapes verified 2026-11-10 against
/// https://platform.claude.com/docs/en/build-with-claude/streaming :
/// `message_start`, `content_block_start`, `ping`, `content_block_delta` with
/// `delta:{type:"text_delta",text}`, `content_block_stop`, `message_delta` with
/// `delta.stop_reason`, `message_stop`, and `error` with `error:{type,message}`.
/// Like the OpenAI-compatible envelope it accepts no tool use and never treats EOF as completion.
public struct ExplanationAnthropicStream: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case malformedEnvelope, oversizedEnvelope, unsupportedToolCall, refused
        case truncatedCompletion, incompleteStream, trailingData, cancelled
        /// The API's own error type, such as "overloaded_error" or "rate_limit_error".
        case providerError(String)
    }

    private var scenes: ExplanationEventStream
    private var line = Data()
    private var total = 0
    private var sawStop = false
    private var sawMessageStop = false
    private var failed = false
    public private(set) var isComplete = false

    public init(sessionID: UUID, turnID: UUID, sceneID: UUID, baseRevision: Int,
                profile: ExplanationWireProfile = .v1) throws {
        scenes = try .init(sessionID: sessionID, turnID: turnID, sceneID: sceneID,
                           baseRevision: baseRevision, profile: profile)
    }

    public mutating func append(_ bytes: Data) throws -> [ExplanationEvent] {
        guard !failed else { throw Failure.cancelled }
        guard !isComplete else { throw Failure.trailingData }
        do {
            guard bytes.count <= 2_097_152 - total else { throw Failure.oversizedEnvelope }
            total += bytes.count
            var events: [ExplanationEvent] = []
            for byte in bytes {
                if byte == 10 {
                    if line.last == 13 { line.removeLast() }
                    events += try acceptLine()
                    line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < 131_072 else { throw Failure.oversizedEnvelope }
                    line.append(byte)
                }
            }
            return events
        } catch { failed = true; scenes.cancel(); throw error }
    }

    public mutating func finish() throws {
        guard !failed else { throw Failure.cancelled }
        guard line.isEmpty, sawStop, sawMessageStop else {
            failed = true; scenes.cancel(); throw Failure.incompleteStream
        }
        try scenes.finish()
        isComplete = true
    }

    public mutating func cancel() { failed = true; scenes.cancel(); line.removeAll() }

    private mutating func acceptLine() throws -> [ExplanationEvent] {
        guard let text = String(data: line, encoding: .utf8) else { throw Failure.malformedEnvelope }
        // `event:` names are redundant with the JSON `type`; blank lines and comments carry nothing.
        if text.isEmpty || text.hasPrefix(":") || text.hasPrefix("event:") { return [] }
        guard text.hasPrefix("data:") else { throw Failure.malformedEnvelope }
        let payload = Data(text.dropFirst(5).drop(while: { $0 == " " }).utf8)
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = object["type"] as? String else { throw Failure.malformedEnvelope }
        switch type {
        case "message_start", "content_block_start", "content_block_stop", "ping": return []
        case "error":
            let kind = (object["error"] as? [String: Any])?["type"] as? String
            throw Failure.providerError(kind ?? "unknown")
        case "content_block_delta":
            guard !sawStop, let delta = object["delta"] as? [String: Any], let kind = delta["type"] as? String else {
                throw Failure.trailingData
            }
            switch kind {
            case "text_delta":
                guard let text = delta["text"] as? String else { throw Failure.malformedEnvelope }
                return text.isEmpty ? [] : try scenes.append(Data(text.utf8))
            case "input_json_delta": throw Failure.unsupportedToolCall
            default: return [] // thinking and signature deltas carry no scene text
            }
        case "message_delta":
            guard !sawStop else { throw Failure.trailingData }
            let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String
            switch reason {
            case "end_turn", "stop_sequence": sawStop = true
            case "refusal": throw Failure.refused
            case "tool_use": throw Failure.unsupportedToolCall
            case nil: break
            default: throw Failure.truncatedCompletion
            }
            return []
        case "message_stop":
            guard sawStop, !sawMessageStop else { throw Failure.incompleteStream }
            sawMessageStop = true
            return []
        default:
            return [] // unknown future event types are ignored, as the docs advise
        }
    }
}
