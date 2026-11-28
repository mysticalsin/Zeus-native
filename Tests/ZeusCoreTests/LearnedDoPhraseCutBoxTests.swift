import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the phrase cut before " do ". These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Learned do phrase cut box")
struct LearnedDoPhraseCutBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedDoPhraseCutBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedDoPhraseCutBox.blankScalars.count == 5)
        #expect(LearnedDoPhraseCutBox.blankScalars.contains(" "))
        #expect(LearnedDoPhraseCutBox.blankScalars.contains("\t"))
        #expect(LearnedDoPhraseCutBox.blankScalars.contains("\n"))
        #expect(LearnedDoPhraseCutBox.blankScalars.contains("\r"))
        #expect(LearnedDoPhraseCutBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedDoPhraseCutBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedDoPhraseCutBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedDoPhraseCutBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedDoPhraseCut() {
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\u{200B}") == "\u{200B}")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut(" \u{200B} ") == "\u{200B}")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\u{200B}focus") == "\u{200B}focus")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("focus\u{200B}") == "focus\u{200B}")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut(" \t\n\r\u{00A0}") == "")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("") == "")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\u{000B}focus") == "\u{000B}focus")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\u{3000}focus") == "\u{3000}focus")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut(" \tfocus\r\n") == "focus")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("\u{00A0}focus\u{00A0}") == "focus")
        #expect(LearnedDoPhraseCutBox.trimmedDoPhraseCut("focus") == "focus")
    }

    @Test func aZeroWidthSpaceStaysOnTheParsedDoPhrase() {
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack")?.phrase == "focus\u{200B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000} do close Slack")?.phrase == "focus\u{3000}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus \u{200B} do close Slack")?.phrase == "focus \u{200B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack and open Notes")?.phrase == "focus\u{200B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus\n do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\n do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\r do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\r do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{00A0} do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus  do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\t do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{3000}focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B} do close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{000B} do close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{3000} do close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B}, close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\n, close Slack")?.phrase == "focus\n")
        #expect(NamedShortcutPhrase.parse("when i say focus\r, close Slack")?.phrase == "focus\r")
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{000B}close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode do close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode do close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("  when i say focus do close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus do close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("When I say focus mode do close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode do close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack then open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("focus do close Slack") == nil)
    }
}
