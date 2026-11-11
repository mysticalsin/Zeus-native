import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationCompletionStreamTests {
    private let session = UUID(), turn = UUID(), scene = UUID()
    private func parser() throws -> ExplanationCompletionStream {
        try .init(sessionID: session, turnID: turn, sceneID: scene, baseRevision: 0)
    }
    private func event() -> ExplanationEvent {
        .init(sessionID: session, turnID: turn, sceneID: scene, sequence: 0, baseRevision: 0,
              revision: 1, beatID: "beat", speech: .init(chunkID: "speech", text: "A circle."), cues: [], isFinal: true)
    }
    private func envelope(_ delta: [String: Any], finish: Any = NSNull()) throws -> Data {
        var data = Data("data: ".utf8)
        data.append(try JSONSerialization.data(withJSONObject: ["choices": [["index": 0, "delta": delta, "finish_reason": finish]]]))
        data.append(contentsOf: "\n\n".utf8); return data
    }
    @Test func validBytewiseStreamRequiresStopDoneAndEOF() throws {
        let expected = event()
        let text = String(decoding: try ExplanationWire.encode(expected), as: UTF8.self) + "\n"
        var bytes = try envelope(["role": "assistant", "content": text])
        bytes.append(try envelope([:], finish: "stop")); bytes.append(contentsOf: "data: [DONE]\n\n".utf8)
        var stream = try parser(), events: [ExplanationEvent] = []
        for byte in bytes { events += try stream.append(Data([byte])) }
        #expect(events == [expected]); #expect(!stream.isComplete)
        try stream.finish(); #expect(stream.isComplete)
    }
    @Test func eofWithoutDoneFailsEvenAfterFinalScene() throws {
        var stream = try parser()
        _ = try stream.append(envelope(["content": String(decoding: ExplanationWire.encode(event()), as: UTF8.self) + "\n"], finish: "stop"))
        #expect(throws: ExplanationCompletionStream.Failure.incompleteStream) { try stream.finish() }
    }
    @Test func outputLimitAndToolsAreVisibleFailures() throws {
        var short = try parser()
        #expect(throws: ExplanationCompletionStream.Failure.truncatedCompletion) { _ = try short.append(envelope([:], finish: "length")) }
        var tools = try parser()
        #expect(throws: ExplanationCompletionStream.Failure.unsupportedToolCall) { _ = try tools.append(envelope(["tool_calls": []])) }
    }
    @Test func malformedJSONAndOversizedLineFailClosed() throws {
        var malformed = try parser()
        #expect(throws: (any Error).self) { _ = try malformed.append(Data("data: {\n\n".utf8)) }
        #expect(throws: ExplanationCompletionStream.Failure.cancelled) { _ = try malformed.append(Data()) }
        var large = try parser()
        #expect(throws: ExplanationCompletionStream.Failure.oversizedEnvelope) { _ = try large.append(Data(repeating: 65, count: 131_073)) }
    }
    @Test func doneBeforeStopAndTruncatedFramingFail() throws {
        var early = try parser()
        #expect(throws: ExplanationCompletionStream.Failure.incompleteStream) { _ = try early.append(Data("data: [DONE]\n\n".utf8)) }
        var incomplete = try parser()
        _ = try incomplete.append(Data("data: {\"choices\":[]}".utf8))
        #expect(throws: ExplanationCompletionStream.Failure.incompleteStream) { try incomplete.finish() }
    }
    @Test func cancellationRejectsLateData() throws {
        var stream = try parser(); stream.cancel()
        #expect(throws: ExplanationCompletionStream.Failure.cancelled) { _ = try stream.append(Data("data: [DONE]\n\n".utf8)) }
    }
}
