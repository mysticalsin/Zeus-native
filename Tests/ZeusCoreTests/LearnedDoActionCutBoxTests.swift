import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the action cut after " do ". These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Learned do action cut box")
struct LearnedDoActionCutBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedDoActionCutBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedDoActionCutBox.blankScalars.count == 5)
        #expect(LearnedDoActionCutBox.blankScalars.contains(" "))
        #expect(LearnedDoActionCutBox.blankScalars.contains("\t"))
        #expect(LearnedDoActionCutBox.blankScalars.contains("\n"))
        #expect(LearnedDoActionCutBox.blankScalars.contains("\r"))
        #expect(LearnedDoActionCutBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedDoActionCutBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedDoActionCutBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedDoActionCutBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedDoActionCut() {
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{200B}") == "\u{200B}")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut(" \u{200B} ") == "\u{200B}")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{200B}close") == "\u{200B}close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("close\u{200B}") == "close\u{200B}")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut(" \t\n\r\u{00A0}") == "")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("") == "")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{000B}close") == "\u{000B}close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{3000}close") == "\u{3000}close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut(" \tclose\r\n") == "close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{00A0}close\u{00A0}") == "close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("close") == "close")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\u{200B}do close Slack") == "\u{200B}do close Slack")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\ndo close Slack") == "do close Slack")
        #expect(LearnedDoActionCutBox.trimmedDoActionCut("\rdo close Slack") == "do close Slack")
    }

    @Test func aZeroWidthSpaceStaysAheadOfDoOnTheDoAction() {
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{000B}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{3000}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}do close Slack and open Notes")?.steps == ["do close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \ndo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \rdo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{00A0}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do  do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \tdo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack\u{200B}")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \nclose Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack\r")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{00A0}close Slack\u{00A0}")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{000B}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{3000}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus do \n\t \u{00A0}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000} do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\n do close Slack")?.phrase == "focus\n")
        #expect(NamedShortcutPhrase.parse("when i say focus\r do close Slack")?.phrase == "focus\r")
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{000B}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{3000}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \ndo close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B}, close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\n, close Slack")?.phrase == "focus\n")
        #expect(NamedShortcutPhrase.parse("when i say focus\r, close Slack")?.phrase == "focus\r")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode do close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode do close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("  when i say focus do close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus do close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("When I say focus mode do close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode do close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack then open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do Do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("focus do close Slack") == nil)
    }
}
