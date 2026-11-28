import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the phrase cut before a comma. These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Learned phrase cut box")
struct LearnedPhraseCutBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedPhraseCutBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedPhraseCutBox.blankScalars.count == 5)
        #expect(LearnedPhraseCutBox.blankScalars.contains(" "))
        #expect(LearnedPhraseCutBox.blankScalars.contains("\t"))
        #expect(LearnedPhraseCutBox.blankScalars.contains("\n"))
        #expect(LearnedPhraseCutBox.blankScalars.contains("\r"))
        #expect(LearnedPhraseCutBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedPhraseCutBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedPhraseCutBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedPhraseCutBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPhraseCut() {
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\u{200B}") == "\u{200B}")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut(" \u{200B} ") == "\u{200B}")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\u{200B}focus") == "\u{200B}focus")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("focus\u{200B}") == "focus\u{200B}")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut(" \t\n\r\u{00A0}") == "")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("") == "")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\u{000B}focus") == "\u{000B}focus")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\u{3000}focus") == "\u{3000}focus")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut(" \tfocus\r\n") == "focus")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("\u{00A0}focus\u{00A0}") == "focus")
        #expect(LearnedPhraseCutBox.trimmedPhraseCut("focus") == "focus")
    }

    @Test func aVerticalTabStaysOnTheParsedPhrase() {
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B}, close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B}, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B}, close Slack")?.phrase == "focus\u{200B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B}, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000}, close Slack")?.phrase == "focus\u{3000}")
        #expect(NamedShortcutPhrase.parse("when i say focus \u{200B}, close Slack")?.phrase == "focus \u{200B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\n, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\r, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus , close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\t, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{00A0}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{3000}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{3000}, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("focus, close Slack") == nil)
    }
}
