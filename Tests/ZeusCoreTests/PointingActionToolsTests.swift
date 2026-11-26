import Foundation
import Testing
@testable import ZeusCore

@Suite("Pointing action tools")
struct PointingActionToolsTests {
    private let secureExplanation = "The focused field is a password field, so I'll leave that one to you."

    @Test func riskyInsertWaitsAndDoesNotCallTheSink() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(risk: .risky), sink: sink)
        #expect(card(from: phase)?.summary == "Insert the note")
        #expect(sink.inserts.isEmpty)
        #expect(sink.clips.isEmpty)
    }

    @Test func acceptInsertsOnceAndShowsTheSummary() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(text: "hello from the note", risk: .risky), sink: sink)
        let phase = tools.accept("a1", sink: sink)
        #expect(indicator(from: phase)?.state == .done)
        #expect(indicator(from: phase)?.summary == "Insert the note")
        #expect(indicator(from: phase)?.summary.contains("hello from the note") == false)
        #expect(sink.inserts == ["hello from the note"])
        #expect(sink.clips.isEmpty)
        let again = tools.accept("a1", sink: sink)
        #expect(indicator(from: again)?.state == .done)
        #expect(sink.inserts == ["hello from the note"])
    }

    @Test func declineLeavesTheFieldUntouched() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let asked = tools.submit(make(risk: .destructive), sink: sink)
        #expect(card(from: asked) != nil)
        let phase = tools.decline("a1")
        #expect(phase == .idle)
        #expect(sink.inserts.isEmpty)
        let late = tools.accept("a1", sink: sink)
        #expect(late == .idle)
        #expect(sink.inserts.isEmpty)
    }

    @Test func cancelLeavesTheFieldUntouchedAndShowsCancelled() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(risk: .risky), sink: sink)
        let phase = tools.cancel("a1")
        #expect(indicator(from: phase)?.state == .cancelled)
        #expect(indicator(from: phase)?.summary == "Insert the note")
        #expect(sink.inserts.isEmpty)
        _ = tools.accept("a1", sink: sink)
        #expect(sink.inserts.isEmpty)
    }

    @Test func sendDeletePurchaseAndPublishAskEvenWhenMarkedSafe() {
        for privilege in [PointingActionRequest.Privilege.send, .delete, .purchase, .publish] {
            let sink = RecordingSink()
            var tools = PointingActionTools()
            let phase = tools.submit(make(risk: .safe, privilege: privilege), sink: sink)
            #expect(card(from: phase)?.id == "a1")
            #expect(sink.inserts.isEmpty)
        }
    }

    @Test func aSummaryThatSaysPublishStillAsks() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(summary: "Publish the draft", risk: .safe), sink: sink)
        #expect(card(from: phase)?.summary == "Publish the draft")
        #expect(sink.inserts.isEmpty)
    }

    @Test func textThatSaysDeleteStillAsks() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(text: "delete the old line", risk: .undoable), sink: sink)
        #expect(card(from: phase) != nil)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aSecureFieldIsRefusedWithoutACard() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(text: "hunter2-unique", risk: .safe, focusedFieldIsSecure: true), sink: sink)
        let refusal = refusal(from: phase)
        #expect(refusal?.reason == .secureField)
        #expect(refusal?.explanation == secureExplanation)
        #expect(refusal?.explanation.contains("hunter2-unique") == false)
        #expect(card(from: phase) == nil)
        #expect(sink.inserts.isEmpty)
        _ = tools.accept("a1", sink: sink)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aSecureFieldBeatsASend() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(
            make(risk: .safe, privilege: .send, focusedFieldIsSecure: true),
            sink: sink
        )
        #expect(refusal(from: phase)?.reason == .secureField)
        #expect(card(from: phase) == nil)
        #expect(sink.inserts.isEmpty)
    }

    @Test func acceptRefusesWhenTheFieldBecameSecure() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(text: "hunter2-unique", risk: .risky), sink: sink)
        let phase = tools.accept("a1", focusedFieldIsSecure: true, sink: sink)
        #expect(refusal(from: phase)?.reason == .secureField)
        #expect(refusal(from: phase)?.explanation.contains("hunter2-unique") == false)
        #expect(sink.inserts.isEmpty)
        _ = tools.accept("a1", sink: sink)
        #expect(sink.inserts.isEmpty)
    }

    @Test func clipboardAlwaysAsksEvenWhenMarkedSafe() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let request = make(kind: .writeClipboard, summary: "Copy a suggested file name", text: "Quarterly-report.pdf", risk: .safe)
        let asked = tools.submit(request, sink: sink)
        #expect(card(from: asked)?.kind == .writeClipboard)
        #expect(sink.clips.isEmpty)
        #expect(sink.inserts.isEmpty)
        let done = tools.accept(request.id, sink: sink)
        #expect(indicator(from: done)?.state == .done)
        #expect(indicator(from: done)?.summary == "Copy a suggested file name")
        #expect(sink.clips == ["Quarterly-report.pdf"])
        #expect(sink.inserts.isEmpty)
    }

    @Test func decliningClipboardWritesNothing() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let asked = tools.submit(make(kind: .writeClipboard, risk: .destructive), sink: sink)
        #expect(card(from: asked)?.kind == .writeClipboard)
        #expect(tools.decline("a1") == .idle)
        #expect(sink.clips.isEmpty)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aSecureFieldDoesNotBlockAClipboardCard() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(kind: .writeClipboard, risk: .safe, focusedFieldIsSecure: true), sink: sink)
        #expect(card(from: phase)?.kind == .writeClipboard)
        #expect(refusal(from: phase) == nil)
        #expect(sink.clips.isEmpty)
    }

    @Test func anOrdinaryInsertRunsWithoutAsking() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(text: "hello", risk: .undoable), sink: sink)
        #expect(card(from: phase) == nil)
        #expect(indicator(from: phase)?.state == .done)
        #expect(sink.inserts == ["hello"])
    }

    @Test func aSafeInsertRunsWithoutAsking() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(risk: .safe), sink: sink)
        #expect(indicator(from: phase)?.state == .done)
        #expect(sink.inserts == ["hello"])
    }

    @Test func emptyTextDoesNotRun() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(text: "   ", risk: .undoable), sink: sink)
        #expect(refusal(from: phase)?.reason == .emptyText)
        #expect(sink.inserts.isEmpty)
    }

    @Test func textPastTheLimitDoesNotRun() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let text = String(repeating: "a", count: PointingActionRequest.maxTextBytes + 1)
        let phase = tools.submit(make(text: text, risk: .undoable), sink: sink)
        #expect(refusal(from: phase)?.reason == .textTooLong)
        #expect(refusal(from: phase)?.explanation.contains(text) == false)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aSummaryPastTheLimitDoesNotRun() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let summary = String(repeating: "b", count: PointingActionRequest.maxSummaryBytes + 1)
        let phase = tools.submit(make(summary: summary, risk: .undoable), sink: sink)
        #expect(refusal(from: phase)?.reason == .summary)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aMissingIdentifierDoesNotRun() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        let phase = tools.submit(make(id: "", risk: .undoable), sink: sink)
        #expect(refusal(from: phase)?.reason == .identifier)
        #expect(sink.inserts.isEmpty)
    }

    @Test func aNewRequestDropsTheEarlierCard() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(id: "first", text: "one", risk: .risky), sink: sink)
        let second = tools.submit(make(id: "second", text: "two", risk: .risky), sink: sink)
        #expect(card(from: second)?.id == "second")
        _ = tools.accept("first", sink: sink)
        #expect(sink.inserts.isEmpty)
        _ = tools.accept("second", sink: sink)
        #expect(sink.inserts == ["two"])
    }

    @Test func decliningTheWrongCardDoesNotDropIt() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(risk: .risky), sink: sink)
        #expect(card(from: tools.decline("other")) != nil)
        _ = tools.accept("a1", sink: sink)
        #expect(sink.inserts == ["hello"])
    }

    @Test func cancellingAfterTheActionDoesNotRunAgain() {
        let sink = RecordingSink()
        var tools = PointingActionTools()
        _ = tools.submit(make(text: "hello", risk: .undoable), sink: sink)
        _ = tools.cancel("a1")
        #expect(sink.inserts == ["hello"])
        #expect(indicator(from: tools.phase)?.state == .done)
    }

    private func make(
        id: String = "a1",
        kind: PointingActionRequest.Kind = .insertText,
        summary: String = "Insert the note",
        text: String = "hello",
        risk: PointingActionRequest.Risk,
        privilege: PointingActionRequest.Privilege = .none,
        focusedFieldIsSecure: Bool = false
    ) -> PointingActionRequest {
        PointingActionRequest(
            id: id,
            kind: kind,
            summary: summary,
            text: text,
            risk: risk,
            privilege: privilege,
            focusedFieldIsSecure: focusedFieldIsSecure
        )
    }

    private func card(from phase: PointingActionPhase) -> PointingActionCard? {
        if case .confirming(let card) = phase { return card }
        return nil
    }

    private func indicator(from phase: PointingActionPhase) -> PointingActionIndicator? {
        if case .indicated(let indicator) = phase { return indicator }
        return nil
    }

    private func refusal(from phase: PointingActionPhase) -> PointingActionRefusal? {
        if case .refused(let refusal) = phase { return refusal }
        return nil
    }
}

private final class RecordingSink: PointingActionSink {
    private(set) var inserts: [String] = []
    private(set) var clips: [String] = []

    func insertText(_ text: String) { inserts.append(text) }
    func writeClipboard(_ text: String) { clips.append(text) }
}
