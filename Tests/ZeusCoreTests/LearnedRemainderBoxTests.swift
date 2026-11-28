import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the remainder after "when i say". These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Learned remainder box")
struct LearnedRemainderBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedRemainderBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedRemainderBox.blankScalars.count == 5)
        #expect(LearnedRemainderBox.blankScalars.contains(" "))
        #expect(LearnedRemainderBox.blankScalars.contains("\t"))
        #expect(LearnedRemainderBox.blankScalars.contains("\n"))
        #expect(LearnedRemainderBox.blankScalars.contains("\r"))
        #expect(LearnedRemainderBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedRemainderBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedRemainderBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedRemainderBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedRemainder() {
        #expect(LearnedRemainderBox.trimmedRemainder("\u{200B}") == "\u{200B}")
        #expect(LearnedRemainderBox.trimmedRemainder(" \u{200B} ") == "\u{200B}")
        #expect(LearnedRemainderBox.trimmedRemainder("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedRemainderBox.trimmedRemainder("\u{200B}focus, close Slack") == "\u{200B}focus, close Slack")
        #expect(LearnedRemainderBox.trimmedRemainder("focus, close Slack\u{200B}") == "focus, close Slack\u{200B}")
        #expect(LearnedRemainderBox.trimmedRemainder(" \t\n\r\u{00A0}") == "")
        #expect(LearnedRemainderBox.trimmedRemainder("") == "")
        #expect(LearnedRemainderBox.trimmedRemainder("\u{000B}focus, close Slack") == "\u{000B}focus, close Slack")
        #expect(LearnedRemainderBox.trimmedRemainder("\u{3000}focus, close Slack") == "\u{3000}focus, close Slack")
        #expect(LearnedRemainderBox.trimmedRemainder(" \tfocus, close Slack\r\n") == "focus, close Slack")
        #expect(LearnedRemainderBox.trimmedRemainder("\u{00A0}focus, close Slack\u{00A0}") == "focus, close Slack")
        #expect(LearnedRemainderBox.trimmedRemainder("focus, close Slack") == "focus, close Slack")
    }

    @Test func aVerticalTabStaysOnTheParsedRemainder() {
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus, close Slack")?.phrase == "\u{000B}focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \n\u{000B}focus, close Slack")?.phrase == "\u{000B}focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}, close Slack")?.phrase == "\u{000B}")
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus do close Slack")?.phrase == "\u{000B}focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{000B}focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus, close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{3000}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{3000}, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("when i say \u{00A0}focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("\u{00A0}when i say focus, close Slack\u{00A0}")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("focus, close Slack") == nil)
    }
}
