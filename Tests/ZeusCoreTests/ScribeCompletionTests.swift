import Testing
@testable import ZeusCore

@Suite("Scribe durable completion")
struct ScribeCompletionTests {
    private func finalized(_ id: ScribeSessionID) -> ScribeSessionMachine {
        var machine = ScribeSessionMachine()
        _ = machine.start(id, now: 1)
        _ = machine.acknowledgeCapture(id, now: 2)
        _ = machine.captureEnded(id)
        _ = machine.transcriptFinalized(id)
        return machine
    }

    @Test func failedFinalSaveCannotRevealCompletionAndExactPayloadCanBeRetried() {
        let id = ScribeSessionID()
        var machine = finalized(id)
        let payload = ScribeMeetingNotes(summary: "Synthetic summary", privateNotes: "Keep this private note")
        var pending: ScribeMeetingNotes?
        var saved: ScribeMeetingNotes?
        let failed = machine.saveAndCompleteNotes(id) { pending = payload; return false }
        #expect(failed.events.isEmpty)
        #expect(machine.phase == .processing(id))
        #expect(ScribePresentation.state(for: machine.phase) == .writing)
        #expect(pending?.privateNotes == payload.privateNotes)
        let retry = machine.saveAndCompleteNotes(id) { saved = pending; return true }
        #expect(saved == payload)
        #expect(retry.events == [.notesReady(id)])
        #expect(machine.phase == .complete(id))
    }

    @Test func persistencePrecedesTheOnlyCompletionEvent() {
        let id = ScribeSessionID()
        var machine = finalized(id)
        var trace: [String] = []
        let result = machine.saveAndCompleteNotes(id) { trace.append("durable save"); return true }
        for _ in result.events { trace.append("completion") }
        let duplicate = machine.saveAndCompleteNotes(id) { trace.append("duplicate write"); return true }
        #expect(trace == ["durable save", "completion"])
        #expect(duplicate.outcome == .invalid)
    }

    @Test func staleOrUnfinalizedSessionCannotWriteOrComplete() {
        let id = ScribeSessionID(), replacement = ScribeSessionID()
        var machine = finalized(id)
        _ = machine.start(replacement, now: 10)
        var writes = 0
        let stale = machine.saveAndCompleteNotes(id) { writes += 1; return true }
        let starting = machine.saveAndCompleteNotes(replacement) { writes += 1; return true }
        #expect(stale.outcome == .stale)
        #expect(starting.outcome == .invalid)
        _ = machine.acknowledgeCapture(replacement, now: 11)
        _ = machine.captureEnded(replacement)
        let unfinalized = machine.saveAndCompleteNotes(replacement) { writes += 1; return true }
        #expect(unfinalized.outcome == .invalid)
        #expect(writes == 0)
    }
}
