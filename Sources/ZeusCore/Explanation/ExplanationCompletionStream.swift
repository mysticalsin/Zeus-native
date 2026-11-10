import Foundation

/// Bounded OpenAI-compatible SSE envelope around the strict scene NDJSON stream.
/// It does not accept tools, substitute prose for a scene, or treat EOF as completion.
public struct ExplanationCompletionStream: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case malformedEnvelope, oversizedEnvelope, providerRejected, unsupportedToolCall
        case truncatedCompletion, incompleteStream, trailingData, cancelled
    }
    private var scenes: ExplanationEventStream
    private var line = Data()
    private var payload = Data()
    private var total = 0
    private var sawStop = false
    private var sawDone = false
    private var failed = false
    public private(set) var isComplete = false

    public init(sessionID: UUID, turnID: UUID, sceneID: UUID, baseRevision: Int) throws {
        scenes = try .init(sessionID: sessionID, turnID: turnID, sceneID: sceneID, baseRevision: baseRevision)
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
        guard line.isEmpty, payload.isEmpty, sawStop, sawDone else {
            failed = true; scenes.cancel(); throw Failure.incompleteStream
        }
        isComplete = true
    }

    public mutating func cancel() { failed = true; scenes.cancel(); line.removeAll(); payload.removeAll() }

    private mutating func acceptLine() throws -> [ExplanationEvent] {
        guard let text = String(data: line, encoding: .utf8) else { throw Failure.malformedEnvelope }
        if text.isEmpty {
            guard !payload.isEmpty else { return [] }
            defer { payload.removeAll(keepingCapacity: true) }
            return try acceptPayload()
        }
        if text.hasPrefix(":") { return [] }
        // EventSource framing is permitted; only data is passed to JSON parsing.
        if text == "event: message" { return [] }
        guard text.hasPrefix("data:"), !sawDone else { throw Failure.trailingData }
        let value = text.dropFirst(5).drop(while: { $0 == " " })
        guard payload.count + value.utf8.count + 1 <= 262_144 else { throw Failure.oversizedEnvelope }
        if !payload.isEmpty { payload.append(10) }
        payload.append(contentsOf: value.utf8)
        return []
    }

    private mutating func acceptPayload() throws -> [ExplanationEvent] {
        if payload == Data("[DONE]".utf8) {
            guard sawStop, !sawDone else { throw Failure.incompleteStream }
            try scenes.finish(); sawDone = true
            return []
        }
        guard !sawDone,
              let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["error"] == nil,
              let choices = object["choices"] as? [[String: Any]] else { throw Failure.providerRejected }
        // An optional usage envelope carries no model output.
        if choices.isEmpty {
            guard object["usage"] != nil else { throw Failure.malformedEnvelope }
            return []
        }
        guard choices.count == 1, let choice = choices.first,
              (choice["index"] as? Int) == 0,
              let delta = choice["delta"] as? [String: Any] else { throw Failure.malformedEnvelope }
        guard delta["tool_calls"] == nil, delta["function_call"] == nil else { throw Failure.unsupportedToolCall }
        if let role = delta["role"] as? String, role != "assistant" { throw Failure.malformedEnvelope }
        if let refusal = delta["refusal"], !(refusal is NSNull) { throw Failure.providerRejected }
        var events: [ExplanationEvent] = []
        if let content = delta["content"], !(content is NSNull) {
            guard let text = content as? String else { throw Failure.malformedEnvelope }
            guard !sawStop || text.isEmpty else { throw Failure.trailingData }
            if !text.isEmpty { events = try scenes.append(Data(text.utf8)) }
        }
        if let reason = choice["finish_reason"], !(reason is NSNull) {
            guard let reason = reason as? String, reason == "stop" else { throw Failure.truncatedCompletion }
            guard !sawStop else { throw Failure.trailingData }
            sawStop = true
        }
        return events
    }
}
