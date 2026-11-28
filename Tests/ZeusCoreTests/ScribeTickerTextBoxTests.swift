import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the ticker-text trim inside `ScribeTickerText.hasWords`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe ticker text box")
struct ScribeTickerTextBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeTickerTextBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeTickerTextBox.blankScalars.count == 5)
        #expect(ScribeTickerTextBox.blankScalars.contains(" "))
        #expect(ScribeTickerTextBox.blankScalars.contains("\t"))
        #expect(ScribeTickerTextBox.blankScalars.contains("\n"))
        #expect(ScribeTickerTextBox.blankScalars.contains("\r"))
        #expect(ScribeTickerTextBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeTickerTextBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeTickerTextBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeTickerTextBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedText() {
        #expect(ScribeTickerTextBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(ScribeTickerTextBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(ScribeTickerTextBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeTickerTextBox.trimmedText("\u{200B}hello") == "\u{200B}hello")
        #expect(ScribeTickerTextBox.trimmedText("hello\u{200B}") == "hello\u{200B}")
        #expect(ScribeTickerTextBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(ScribeTickerTextBox.trimmedText("") == "")
        #expect(ScribeTickerTextBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(ScribeTickerTextBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(ScribeTickerTextBox.trimmedText(" \thello\r\n") == "hello")
        #expect(ScribeTickerTextBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ScribeTickerTextBox.trimmedText("hello") == "hello")
        #expect(ScribeTickerTextBox.trimmedText("hel\u{200B}lo") == "hel\u{200B}lo")
        #expect(ScribeTickerTextBox.trimmedText("\n") == "")
        #expect(ScribeTickerTextBox.trimmedText("\r") == "")
        #expect(ScribeTickerTextBox.trimmedText("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStillCountsAsWords() {
        #expect(ScribeTickerText.hasWords("\u{200B}"))
        #expect(ScribeTickerText.hasWords(" \u{200B} "))
        #expect(ScribeTickerText.hasWords("\t\u{200B}\n"))
        #expect(ScribeTickerText.hasWords("\n\u{200B}\r"))
        #expect(ScribeTickerText.hasWords("\u{200B}hello"))
        #expect(ScribeTickerText.hasWords("hello\u{200B}"))
        #expect(ScribeTickerText.hasWords("hel\u{200B}lo"))
        #expect(ScribeTickerText.hasWords("\u{3000}"))
        #expect(ScribeTickerText.hasWords("\u{3000}hello"))
        #expect(ScribeTickerText.hasWords("\u{000B}"))
        #expect(ScribeTickerText.hasWords("\u{000B}hello"))
        #expect(ScribeTickerText.hasWords(" \thello\r\n"))
        #expect(ScribeTickerText.hasWords("\u{00A0}hello\u{00A0}"))
        #expect(ScribeTickerText.hasWords("hi"))
        #expect(ScribeTickerText.hasWords("hello"))
        #expect(!ScribeTickerText.hasWords("…"))
        #expect(!ScribeTickerText.hasWords(" … "))
        #expect(!ScribeTickerText.hasWords("\u{00A0}…\u{00A0}"))
        #expect(!ScribeTickerText.hasWords("\n…\r"))
        #expect(ScribeTickerText.hasWords("\u{200B}…"))
        #expect(ScribeTickerText.hasWords("…\u{200B}"))
        #expect(ScribeTickerText.hasWords("… hi"))
        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}", "  "] {
            #expect(!ScribeTickerText.hasWords(blank))
        }
    }
}
