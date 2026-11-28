import Foundation
import Testing
@testable import ZeusCore

@Suite("Selection edit box")
struct SelectionEditBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(SelectionEditBox.blankScalars.count == 25)
        #expect(SelectionEditBox.blankScalars.contains(" "))
        #expect(SelectionEditBox.blankScalars.contains("\t"))
        #expect(SelectionEditBox.blankScalars.contains("\n"))
        #expect(SelectionEditBox.blankScalars.contains("\u{000B}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{000C}"))
        #expect(SelectionEditBox.blankScalars.contains("\r"))
        #expect(SelectionEditBox.blankScalars.contains("\u{0085}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{00A0}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{1680}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{2000}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{200A}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{2028}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{2029}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{202F}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{205F}"))
        #expect(SelectionEditBox.blankScalars.contains("\u{3000}"))
        #expect(!SelectionEditBox.blankScalars.contains("\u{200B}"))
        #expect(SelectionEditBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(SelectionEditBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(SelectionEditBox.trimmed(" \t\n\u{00A0}\u{3000}") == "")
        #expect(SelectionEditBox.trimmed("\u{000B}\u{000C}\u{0085}\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}x\u{3000}") == "x")
    }

    @Test func aZeroWidthSpaceBlocksALeadingCommand() {
        #expect(SelectionEditBox.plan(utterance: "\u{200B}insert On my way", selection: "hello") == nil)
        #expect(SelectionEditBox.plan(utterance: "\u{200B}reply to this Thursday", selection: "hello") == nil)
        #expect(SelectionEditBox.plan(utterance: "insert\u{200B} On my way", selection: "hello") == nil)
        #expect(SelectionRewrite.plan(utterance: "\u{200B}insert On my way", selection: "hello") == nil)
        #expect(SelectionRewrite.plan(utterance: "\u{200B}reply to this. Thursday", selection: "kept") == nil)
    }

    @Test func aContainedShorterPhraseStillMatchesWithAZeroWidthSpace() {
        let edit = SelectionEditBox.plan(utterance: "\u{200B}make this shorter", selection: "hello there friend")
        #expect(edit?.kind == .replace)
        #expect(edit?.after == "hello")
        #expect(edit?.sends == false)
        #expect(SelectionRewrite.plan(utterance: "\u{200B}make this shorter", selection: "hello there friend")?.after == "hello")
        #expect(SelectionEditBox.plan(utterance: "make this short\u{200B}er", selection: "hello there friend") == nil)
        #expect(SelectionEditBox.shorter("hello there friend") == "hello")
        #expect(SelectionEditBox.shorter("hello\u{200B}there friend") == "hello\u{200B}there")
        #expect(SelectionEditBox.shorter("a b c d") == "a b")
        #expect(SelectionEditBox.shorter("one") == "one")
        #expect(SelectionEditBox.shorter("  hello  ") == "  hello  ")
        #expect(SelectionRewrite.shorter("hello there friend") == "hello")
    }

    @Test func namedBlanksStillSelectReplyInsertAndShorter() {
        let reply = SelectionEditBox.plan(
            utterance: "\u{00A0}Reply to this.\u{00A0}Thursday works\n",
            selection: "Can you do Thursday?")
        #expect(reply?.kind == .draft)
        #expect(reply?.after == "Thursday works")
        #expect(reply?.sends == false)
        let inserted = SelectionEditBox.plan(utterance: " \tinsert On my way\n", selection: "hello")
        #expect(inserted?.kind == .insert)
        #expect(inserted?.after == "On my way")
        #expect(inserted?.sends == false)
        #expect(SelectionRewrite.plan(utterance: " insert On my way ", selection: "hello")?.after == "On my way")
        let shorter = SelectionEditBox.plan(utterance: "\tmake this shorter\u{3000}", selection: "hello there friend")
        #expect(shorter?.kind == .replace)
        #expect(shorter?.after == "hello")
        #expect(SelectionEditBox.plan(utterance: "insert On\u{200B} my way", selection: "hello")?.after == "On\u{200B} my way")
    }

    @Test func anEmptyInsertIsRefusedAndABlankReplyKeepsTheSelection() {
        #expect(SelectionEditBox.plan(utterance: "insert   ", selection: "hello") == nil)
        #expect(SelectionEditBox.plan(utterance: "\tinsert \u{3000}\n", selection: "hello") == nil)
        let zwsp = SelectionEditBox.plan(utterance: "insert \u{200B}", selection: "hello")
        #expect(zwsp?.kind == .insert)
        #expect(zwsp?.after == "\u{200B}")
        #expect(zwsp?.sends == false)
        let kept = SelectionEditBox.plan(utterance: "reply to this", selection: "kept")
        #expect(kept?.kind == .draft)
        #expect(kept?.after == "kept")
        #expect(kept?.sends == false)
        #expect(SelectionEditBox.plan(utterance: "reply to this.   ", selection: "kept")?.after == "kept")
        #expect(SelectionEditBox.plan(utterance: "reply to this. \u{200B}", selection: "kept")?.after == "\u{200B}")
        #expect(SelectionRewrite.plan(utterance: "insert \u{200B}", selection: "hello")?.after == "\u{200B}")
        #expect(SelectionEditBox.plan(utterance: "   ", selection: "kept") == nil)
    }

    @Test func aSecretSelectionIsNotShownOrRewritten() {
        #expect(SelectionEditBox.plan(utterance: "make this shorter", selection: "password") == nil)
        #expect(SelectionEditBox.plan(utterance: "make this shorter", selection: "API key") == nil)
        #expect(SelectionEditBox.plan(utterance: "insert password", selection: "hello") == nil)
        #expect(SelectionEditBox.plan(utterance: "reply to this. PIN", selection: "hello") == nil)
        let note = SelectionEditBox.plan(utterance: "make this shorter", selection: "change the password tomorrow please")
        #expect(note?.kind == .replace)
        #expect(note?.before == "change the password tomorrow please")
    }
}
