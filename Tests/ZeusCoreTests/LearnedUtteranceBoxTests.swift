import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a learned shortcut utterance. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Learned utterance box")
struct LearnedUtteranceBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedUtteranceBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedUtteranceBox.blankScalars.count == 5)
        #expect(LearnedUtteranceBox.blankScalars.contains(" "))
        #expect(LearnedUtteranceBox.blankScalars.contains("\t"))
        #expect(LearnedUtteranceBox.blankScalars.contains("\n"))
        #expect(LearnedUtteranceBox.blankScalars.contains("\r"))
        #expect(LearnedUtteranceBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedUtteranceBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedUtteranceBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedUtteranceBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedUtterance() {
        #expect(LearnedUtteranceBox.trimmedUtterance("\u{200B}") == "\u{200B}")
        #expect(LearnedUtteranceBox.trimmedUtterance(" \u{200B} ") == "\u{200B}")
        #expect(LearnedUtteranceBox.trimmedUtterance("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedUtteranceBox.trimmedUtterance("\u{200B}when i say focus, close Slack") == "\u{200B}when i say focus, close Slack")
        #expect(LearnedUtteranceBox.trimmedUtterance("when i say focus, close Slack\u{200B}") == "when i say focus, close Slack\u{200B}")
        #expect(LearnedUtteranceBox.trimmedUtterance(" \t\n\r\u{00A0}") == "")
        #expect(LearnedUtteranceBox.trimmedUtterance("") == "")
        #expect(LearnedUtteranceBox.trimmedUtterance("\u{000B}when i say focus, close Slack") == "\u{000B}when i say focus, close Slack")
        #expect(LearnedUtteranceBox.trimmedUtterance("\u{3000}when i say focus, close Slack") == "\u{3000}when i say focus, close Slack")
        #expect(LearnedUtteranceBox.trimmedUtterance(" \twhen i say focus, close Slack\r\n") == "when i say focus, close Slack")
        #expect(LearnedUtteranceBox.trimmedUtterance("\u{00A0}when i say focus, close Slack\u{00A0}") == "when i say focus, close Slack")
        #expect(LearnedUtteranceBox.trimmedUtterance("when i say focus, close Slack") == "when i say focus, close Slack")
    }

    @Test func aZeroWidthSpaceStaysOnTheParsedUtterance() {
        #expect(NamedShortcutPhrase.parse("\u{200B}when i say focus, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse(" \u{200B}when i say focus, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("\t\u{200B}when i say focus, close Slack\n") == nil)
        #expect(NamedShortcutPhrase.parse("\u{200B}When I say focus, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("\u{3000}when i say focus, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("\u{000B}when i say focus, close Slack") == nil)
        #expect(NamedShortcutPhrase.parse("\u{200B}") == nil)
        #expect(NamedShortcutPhrase.parse(" \t\n\r\u{00A0}") == nil)
        #expect(NamedShortcutPhrase.parse("") == nil)
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("  when i say focus, close Slack  ")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("\u{00A0}when i say focus mode, close Slack and open Notes\u{00A0}")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("\u{00A0}when i say focus mode, close Slack and open Notes\u{00A0}")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.phrase == "focus mode")
        #expect(NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes")?.steps == ["close Slack", "open Notes"])
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus do close Slack")?.steps == ["close Slack"])
        #expect(NamedShortcutPhrase.parse("when i say \u{200B}focus, close Slack")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack\u{200B}")?.phrase == "focus")
        #expect(NamedShortcutPhrase.parse("when i say focus, close Slack\u{200B}")?.steps == ["close Slack"])
    }
}
