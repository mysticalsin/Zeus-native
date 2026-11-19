import Foundation
import Testing
@testable import ZeusCore

@Suite struct ExplanationStreamTests {
    private func stream() throws -> ExplanationEventStream {
        try .init(sessionID: ExplanationProtocolFixtures.session, turnID: ExplanationProtocolFixtures.turn,
                  sceneID: ExplanationProtocolFixtures.sceneID, baseRevision: 0)
    }

    @Test func arbitraryByteChunksIncludingSplitUTF8EmitOnlyCompleteEvents() throws {
        var event = ExplanationProtocolFixtures.event(); event.speech.text = "A café and a sphere 🌐."
        let data = try ExplanationProtocolFixtures.line(event)
        var stream = try stream(), output: [ExplanationEvent] = []
        for byte in data.dropLast() { output += try stream.append(Data([byte])); #expect(output.isEmpty) }
        output += try stream.append(Data([10]))
        #expect(output == [event]); try stream.finish()
        #expect(throws: ExplanationFailure.streamFinished) { try stream.append(data) }
    }

    @Test func orderedBatchesAndEquivalentDuplicatesAreIdempotent() throws {
        let first = ExplanationProtocolFixtures.event(final: false)
        let second = ExplanationProtocolFixtures.event(sequence: 1, base: 1, operations: [.move(id: "point", position: .one)])
        var stream = try stream()
        let firstLine = try ExplanationProtocolFixtures.line(first)
        #expect(try stream.append(firstLine) == [first])
        let pretty = JSONEncoder(); pretty.outputFormatting = [.sortedKeys]
        var duplicate = try pretty.encode(first); duplicate.append(contentsOf: [13, 10])
        #expect(try stream.append(duplicate).isEmpty)
        #expect(try stream.append(ExplanationProtocolFixtures.line(second)) == [second])
        #expect(try stream.append(ExplanationProtocolFixtures.line(second)).isEmpty)
        try stream.finish()
    }

    @Test func conflictingDuplicatesSequenceGapsAndWrongBaseRevisionReject() throws {
        let first = ExplanationProtocolFixtures.event(final: false)
        var duplicate = first; duplicate.speech.text = "Different speech"
        var a = try stream(); _ = try a.append(ExplanationProtocolFixtures.line(first))
        #expect(throws: ExplanationFailure.conflictingDuplicate) { try a.append(ExplanationProtocolFixtures.line(duplicate)) }
        var b = try stream()
        let gap = ExplanationProtocolFixtures.event(sequence: 1, base: 1)
        #expect(throws: ExplanationFailure.sequenceGap) { try b.append(ExplanationProtocolFixtures.line(gap)) }
        var c = try stream()
        let wrongRevision = ExplanationProtocolFixtures.event(base: 1)
        #expect(throws: ExplanationFailure.revisionConflict) { try c.append(ExplanationProtocolFixtures.line(wrongRevision)) }
    }

    @Test func staleSessionSceneAndTurnAreRejectedBeforeDeduplication() throws {
        for part in 0..<3 {
            var stale = ExplanationProtocolFixtures.event()
            if part == 0 { stale.sessionID = UUID() }
            if part == 1 { stale.sceneID = UUID() }
            if part == 2 { stale.turnID = UUID() }
            var stream = try stream()
            #expect(throws: ExplanationFailure.staleIdentity) { try stream.append(ExplanationProtocolFixtures.line(stale)) }
        }
    }

    @Test func malformedBatchEmitsNothingAndFailsPermanently() throws {
        var stream = try stream()
        var batch = try ExplanationProtocolFixtures.line(ExplanationProtocolFixtures.event(final: false))
        batch.append(contentsOf: Data("{\"op\":\"execute\"}\n".utf8))
        var output: [ExplanationEvent] = []
        #expect(throws: ExplanationFailure.self) { output = try stream.append(batch) }
        #expect(output.isEmpty)
        #expect(throws: ExplanationFailure.self) { try stream.append(ExplanationProtocolFixtures.line(ExplanationProtocolFixtures.event())) }
    }

    @Test func finishRequiresFinalEventAndFinalNewlineAndCancellationDropsPending() throws {
        var truncated = try stream()
        _ = try truncated.append(ExplanationWire.encode(ExplanationProtocolFixtures.event()))
        #expect(throws: ExplanationFailure.self) { try truncated.finish() }
        var noFinal = try stream()
        _ = try noFinal.append(ExplanationProtocolFixtures.line(ExplanationProtocolFixtures.event(final: false)))
        #expect(throws: ExplanationFailure.self) { try noFinal.finish() }
        var cancelled = try stream(); _ = try cancelled.append(Data("{\"version\":".utf8)); cancelled.cancel()
        #expect(throws: ExplanationFailure.cancelled) { try cancelled.append(Data("1}".utf8)) }
        #expect(throws: ExplanationFailure.cancelled) { try cancelled.finish() }
    }

    @Test func frameTurnAndIdentityBudgetsBoundRetryAndMemory() throws {
        var frame = try stream()
        #expect(throws: ExplanationFailure.self) { try frame.append(Data(repeating: 32, count: ExplanationLimits.frameBytes + 2)) }
        var turn = try stream()
        #expect(throws: ExplanationFailure.limitExceeded("turn bytes")) { try turn.append(Data(repeating: 32, count: ExplanationLimits.turnBytes + 1)) }
        var ids = try stream()
        let first = ExplanationProtocolFixtures.event(final: false)
        _ = try ids.append(ExplanationProtocolFixtures.line(first))
        var second = ExplanationProtocolFixtures.event(sequence: 1, base: 1); second.beatID = first.beatID
        #expect(throws: ExplanationFailure.self) { try ids.append(ExplanationProtocolFixtures.line(second)) }
    }
}
