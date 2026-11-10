import Foundation
import Testing
@testable import ZeusCore

@Suite("Acknowledged dictation ownership")
@MainActor
struct TextInsertionReceiptTests {
    typealias Receipt = TextInsertionReceipt
    typealias State = Receipt.FieldState
    typealias Span = Receipt.Span

    private func states(text: String = "Send it to Paul.") -> (State, State) {
        let owner = Receipt.Owner(pid: 42, bundleID: "test.editor")
        let id = UUID()
        return (
            State(owner: owner, fieldID: id, selection: Span(location: 7, length: 0), characterCount: 7),
            State(owner: owner, fieldID: id, selection: Span(location: 7 + text.utf16.count, length: 0),
                  characterCount: 7 + text.utf16.count, ownedText: text)
        )
    }

    private func receipt(text: String = "Send it to Paul.") -> Receipt {
        let (before, after) = states(text: text)
        return Receipt.acknowledgeInsertion(text: text, before: before, after: after, sendsReturn: false)!
    }

    @Test func onlyProvenPlainEditableRolesSupportReceipts() {
        #expect(Receipt.supportsField(role: "AXTextArea", subrole: .absent, canSelectRange: true, canReplaceSelection: true))
        #expect(Receipt.supportsField(role: "AXTextField", subrole: .absent, canSelectRange: true, canReplaceSelection: true))
        #expect(Receipt.supportsField(role: "AXTextField", subrole: .named("AXSearchField"), canSelectRange: true, canReplaceSelection: true))
        for role in [nil, "AXUnknown", "AXStaticText", "AXSecureTextField"] {
            #expect(!Receipt.supportsField(role: role, subrole: .absent, canSelectRange: true, canReplaceSelection: true))
        }
        for subrole: Receipt.FieldSubrole in [.unreadable, .named("AXSecureTextField"), .named("AXUnknown"), .named("")] {
            #expect(!Receipt.supportsField(role: "AXTextField", subrole: subrole, canSelectRange: true, canReplaceSelection: true))
        }
        #expect(!Receipt.supportsField(role: "AXTextField", subrole: .absent, canSelectRange: false, canReplaceSelection: true))
        #expect(!Receipt.supportsField(role: "AXTextField", subrole: .absent, canSelectRange: true, canReplaceSelection: false))
    }

    @Test func explicitLeadingCommandHasWholeTurnSemantics() {
        #expect(Receipt.correctionPayload("No, I meant send the entire letter to María.") == "send the entire letter to María.")
        #expect(Receipt.correctionPayload("no I meant: Monday instead.") == "Monday instead.")
        #expect(Receipt.correctionPayload(" NO. I MEANT 🚀 tomorrow! ") == "🚀 tomorrow!")
    }

    @Test(arguments: ["Say ‘no, I meant Tuesday’.", "\"No, I meant Tuesday\"", "‘No, I meant Tuesday’",
                      "Email Paul, no, I meant Marc.", "I meant Tuesday.", "Nobody meant Tuesday.",
                      "No, I meant", "No, I meant …", "No, I meant...", "No, I meantness."])
    func ordinaryOrIncompleteSpeechDoesNotRequestReplacement(_ text: String) {
        #expect(Receipt.correctionPayload(text) == nil)
    }

    @Test func acknowledgmentRequiresExactNativeReadback() {
        let (before, after) = states()
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: false) != nil)
        var changed = after
        changed.ownedText = nil
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: changed, sendsReturn: false) == nil)
        changed.ownedText = "Send it to Saul."
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: changed, sendsReturn: false) == nil)
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: true) == nil)
    }

    @Test func selectionReplacementOrInvalidOffsetsNeverEarnReceipt() {
        var (before, after) = states()
        before.selection.length = 1
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: false) == nil)
        before.selection = Span(location: -1, length: 0)
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: false) == nil)
        before.selection = Span(location: Int.max, length: 0)
        before.characterCount = Int.max
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: false) == nil)
        #expect(Span(location: Int.max, length: 1).end == nil)
    }

    @Test(arguments: ["field", "pid", "bundle", "count", "caret", "selection"])
    func acknowledgmentRejectsIdentityCountAndCaretDrift(_ drift: String) {
        var (before, after) = states()
        switch drift {
        case "field": after.fieldID = UUID()
        case "pid": after.owner.pid += 1
        case "bundle": after.owner.bundleID = "another.app"
        case "count": after.characterCount += 1
        case "caret": after.selection.location -= 1
        default: before.selection.length = 1
        }
        #expect(Receipt.acknowledgeInsertion(text: "Send it to Paul.", before: before, after: after, sendsReturn: false) == nil)
    }

    @Test func utf16ReadbackHandlesEmojiAndCombiningMarks() {
        let text = "🚀 Cafe\u{301}"
        let acknowledged = receipt(text: text)
        #expect(acknowledged.span.length == text.utf16.count)
        #expect(acknowledged.span.length != text.count)
    }

    @Test(arguments: ["field", "pid", "bundle", "count", "caret", "text", "selection"])
    func everyOwnershipDriftRefusesBeforeSelecting(_ drift: String) async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        switch drift {
        case "field": sink.state.fieldID = UUID()
        case "pid": sink.state.owner.pid += 1
        case "bundle": sink.state.owner.bundleID = "another.app"
        case "count": sink.state.characterCount += 1
        case "caret": sink.state.selection.location -= 1
        case "text": sink.state.ownedText = "Send it to Saul."
        default: sink.state.selection.length = 1
        }
        let result = await acknowledged.replace(with: "Send it to Marc.", steps: sink.steps)
        #expect(result == .unavailable)
        #expect(sink.selectionCalls == 0)
        #expect(sink.replacements.isEmpty)
    }

    @Test func sameFieldWholeTurnReplacementAcknowledgesAndCanCorrectAgain() async {
        let first = receipt()
        let sink = SyntheticField(first)
        let result = await first.replace(with: "Call María tomorrow.", steps: sink.steps)
        guard case .replaced(let next) = result else { Issue.record("No acknowledgment: \(result)"); return }
        #expect(sink.selectedSpans == [first.span])
        #expect(sink.replacements == ["Call María tomorrow."])
        #expect(next.span.location == first.span.location)
        #expect(next.text == "Call María tomorrow.")
        #expect(next.characterCount == 7 + next.text.utf16.count)
        let again = await next.replace(with: "Call Marc.", steps: sink.steps)
        guard case .replaced(let final) = again else { Issue.record("Repeated correction failed"); return }
        #expect(final.text == "Call Marc.")
        #expect(sink.replacements.count == 2)
    }

    @Test func cancellationBeforeSelectionDoesNothing() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.current = false
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .superseded)
        #expect(sink.selectionCalls == 0)
        #expect(sink.replacements.isEmpty)
    }

    @Test func cancellationInsideInspectionCannotReachSelection() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.afterInspection = { sink.current = false }
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unavailable)
        #expect(sink.selectionCalls == 0)
    }

    @Test func focusDriftOrCancellationAfterSelectionCannotWrite() async {
        for cancelled in [true, false] {
            let acknowledged = receipt()
            let sink = SyntheticField(acknowledged)
            sink.afterSelection = {
                if cancelled { sink.current = false } else { sink.state.fieldID = UUID() }
            }
            #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unavailable)
            #expect(sink.replacements.isEmpty)
        }
    }

    @Test func failedSelectionDoesNotCallTextSetter() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.selectionSucceeds = false
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unavailable)
        #expect(sink.replacements.isEmpty)
    }

    @Test func setterFailureIsUnconfirmedNeverRetries() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.setterSucceeds = false
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unconfirmed)
        #expect(sink.replacements == ["Replacement"])
        #expect(sink.waits == 0)
    }

    @Test func delayedReadbackIsBoundedAndDoesNotRepeatMutation() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.acknowledges = false
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unconfirmed)
        #expect(sink.waits == 3)
        #expect(sink.replacements == ["Replacement"])
    }

    @Test func cancellationWhileAwaitingReadbackNeverRenewsReceipt() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.acknowledges = false
        sink.onWait = { sink.current = false }
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unconfirmed)
        #expect(sink.waits == 1)
        #expect(sink.replacements.count == 1)
    }

    @Test func stateChangedDuringReadbackCannotAcknowledgeStaleTurn() async {
        let acknowledged = receipt()
        let sink = SyntheticField(acknowledged)
        sink.afterInspection = {
            if !sink.replacements.isEmpty { sink.current = false }
        }
        #expect(await acknowledged.replace(with: "Replacement", steps: sink.steps) == .unconfirmed)
        #expect(sink.replacements.count == 1)
    }
}

/// Synthetic AX-like storage: production receipt/executor makes every authorization decision.
/// No accessibility APIs, app focus, pasteboard, CGEvents, audio or network are used in this suite.
@MainActor
private final class SyntheticField {
    typealias Receipt = TextInsertionReceipt
    var state: Receipt.FieldState
    var current = true
    var selectionSucceeds = true
    var setterSucceeds = true
    var acknowledges = true
    var selectionCalls = 0
    var selectedSpans: [Receipt.Span] = []
    var replacements: [String] = []
    var waits = 0
    var afterInspection: (() -> Void)?
    var afterSelection: (() -> Void)?
    var onWait: (() -> Void)?

    init(_ receipt: Receipt) {
        state = Receipt.FieldState(owner: receipt.owner, fieldID: receipt.fieldID,
                                   selection: .init(location: receipt.span.end!, length: 0),
                                   characterCount: receipt.characterCount, ownedText: receipt.text)
    }

    var steps: Receipt.ReplacementSteps {
        .init(isCurrent: { self.current }, inspect: { _ in
            let result = self.state
            self.afterInspection?()
            return result
        }, select: { span in
            self.selectionCalls += 1
            guard self.selectionSucceeds else { return false }
            self.state.selection = span
            self.selectedSpans.append(span)
            self.afterSelection?()
            return true
        }, replaceSelected: { text in
            self.replacements.append(text)
            guard self.setterSucceeds else { return false }
            if self.acknowledges {
                self.state.characterCount += text.utf16.count - self.state.selection.length
                self.state.selection = .init(location: self.state.selection.location + text.utf16.count, length: 0)
                self.state.ownedText = text
            }
            return true
        }, waitForAcknowledgment: {
            self.waits += 1
            self.onWait?()
        })
    }
}
