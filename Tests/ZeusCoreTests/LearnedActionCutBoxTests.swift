import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the action cut beside a comma. These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Learned action cut box")
struct LearnedActionCutBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedActionCutBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedActionCutBox.blankScalars.count == 5)
        #expect(LearnedActionCutBox.blankScalars.contains(" "))
        #expect(LearnedActionCutBox.blankScalars.contains("\t"))
        #expect(LearnedActionCutBox.blankScalars.contains("\n"))
        #expect(LearnedActionCutBox.blankScalars.contains("\r"))
        #expect(LearnedActionCutBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedActionCutBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedActionCutBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedActionCutBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedActionCut() {
        #expect(LearnedActionCutBox.trimmedActionCut("\u{200B}") == "\u{200B}")
        #expect(LearnedActionCutBox.trimmedActionCut(" \u{200B} ") == "\u{200B}")
        #expect(LearnedActionCutBox.trimmedActionCut("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedActionCutBox.trimmedActionCut("\u{200B}close") == "\u{200B}close")
        #expect(LearnedActionCutBox.trimmedActionCut("close\u{200B}") == "close\u{200B}")
        #expect(LearnedActionCutBox.trimmedActionCut(" \t\n\r\u{00A0}") == "")
        #expect(LearnedActionCutBox.trimmedActionCut("") == "")
        #expect(LearnedActionCutBox.trimmedActionCut("\u{000B}close") == "\u{000B}close")
        #expect(LearnedActionCutBox.trimmedActionCut("\u{3000}close") == "\u{3000}close")
        #expect(LearnedActionCutBox.trimmedActionCut(" \tclose\r\n") == "close")
        #expect(LearnedActionCutBox.trimmedActionCut("\u{00A0}close\u{00A0}") == "close")
        #expect(LearnedActionCutBox.trimmedActionCut("close") == "close")
        #expect(LearnedActionCutBox.trimmedActionCut("\u{200B}do close Slack") == "\u{200B}do close Slack")
        #expect(LearnedActionCutBox.trimmedActionCut("\ndo close Slack") == "do close Slack")
        #expect(LearnedActionCutBox.trimmedActionCut("\rdo close Slack") == "do close Slack")
    }

    @Test func aZeroWidthSpaceStaysAheadOfDoOnTheCommaAction() {
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{000B}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{3000}do close Slack")?.steps == ["do close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}do close Slack and open Notes")?.steps == ["do close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \ndo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \rdo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{00A0}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus,  do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \tdo close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack\u{200B}")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \nclose Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack\r")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus,\u{00A0}close Slack\u{00A0}")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{000B}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus, \u{3000}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus, \n\t \u{00A0}") == nil)
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B}, close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{3000}, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\n, close Slack")?.phrase == "focus\n")
        #expect(NamedShortcutPhrase.parse("when i say focus\r, close Slack")?.phrase == "focus\r")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{200B} do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.phrase == "focus\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say focus\u{000B} do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus do \u{200B}do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack then open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say focus, Do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("focus, close Slack") == nil)
    }
}
