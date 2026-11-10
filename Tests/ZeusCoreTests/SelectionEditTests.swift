import Testing
@testable import ZeusCore

@Suite struct SelectionEditTests {
    @Test func shorterReplacesInPlaceAndRestoresTheClipboard() {
        let edit = SelectionRewrite.plan(utterance: "make this shorter", selection: "hello there friend")
        #expect(edit?.kind == .replace)
        #expect(edit?.after == "hello")
        #expect(edit?.sends == false)
        #expect(edit?.diff.contains { $0.kind == .removed && $0.text == "hello there friend" } == true)
        #expect(edit?.diff.contains { $0.kind == .added && $0.text == "hello" } == true)
        var session = SelectionEditSession(edit: edit!, clipboard: "copied-note")
        #expect(session.appliedText == nil)
        session.accept()
        #expect(session.appliedText == "hello")
        #expect(session.clipboard.restored() == "copied-note")
        #expect(!session.sendPressed)
    }

    @Test func replyDraftsAndDoesNotSend() {
        let edit = SelectionRewrite.plan(utterance: "Reply to this. Thursday works", selection: "Can you do Thursday?")
        #expect(edit?.kind == .draft)
        #expect(edit?.after == "Thursday works")
        #expect(edit?.sends == false)
        var session = SelectionEditSession(edit: edit!, clipboard: "copied-note")
        let send = session.sendPressed
        session.accept()
        #expect(session.sendPressed == send)
        #expect(!session.sendPressed)
        #expect(session.appliedText == "Thursday works")
        #expect(session.clipboard.restored() == "copied-note")
    }

    @Test func insertKeepsTheDraftFromSending() {
        let edit = SelectionRewrite.plan(utterance: "insert On my way", selection: "hello")
        #expect(edit?.kind == .insert)
        #expect(edit?.after == "On my way")
        #expect(edit?.sends == false)
    }

    @Test func acceptancePasses() {
        let report = SelectionAcceptance.report()
        #expect(report.passed)
        #expect(report.text.hasPrefix("PASS"))
    }
}
