import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a dictate-file transcript. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Dictation file inject box")
struct DictationFileInjectBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(DictationFileInjectBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(DictationFileInjectBox.blankScalars.count == 5)
        #expect(DictationFileInjectBox.blankScalars.contains(" "))
        #expect(DictationFileInjectBox.blankScalars.contains("\t"))
        #expect(DictationFileInjectBox.blankScalars.contains("\n"))
        #expect(DictationFileInjectBox.blankScalars.contains("\r"))
        #expect(DictationFileInjectBox.blankScalars.contains("\u{00A0}"))
        #expect(!DictationFileInjectBox.blankScalars.contains("\u{200B}"))
        #expect(!DictationFileInjectBox.blankScalars.contains("\u{000B}"))
        #expect(!DictationFileInjectBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTrimmedText() {
        #expect(DictationFileInjectBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(DictationFileInjectBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(DictationFileInjectBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(DictationFileInjectBox.trimmedText("\u{200B}fox") == "\u{200B}fox")
        #expect(DictationFileInjectBox.trimmedText("fox\u{200B}") == "fox\u{200B}")
        #expect(DictationFileInjectBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(DictationFileInjectBox.trimmedText("") == "")
        #expect(DictationFileInjectBox.trimmedText("\u{000B}fox") == "\u{000B}fox")
        #expect(DictationFileInjectBox.trimmedText("\u{3000}fox") == "\u{3000}fox")
        #expect(DictationFileInjectBox.trimmedText(" \tfox\r\n") == "fox")
        #expect(DictationFileInjectBox.trimmedText("\u{00A0}fox\u{00A0}") == "fox")
        #expect(DictationFileInjectBox.trimmedText("a\u{00A0}b") == "a\u{00A0}b")
    }

    @Test func aZeroWidthSpaceStillCountsAsInsertedText() {
        #expect(DictationFileInject.reply(inserted: true, resultText: "\u{200B}", failureMessage: nil) == "ok")
        #expect(DictationFileInject.reply(inserted: true, resultText: " \u{200B} ", failureMessage: nil) == "ok")
        #expect(DictationFileInject.reply(inserted: true, resultText: "\u{000B}", failureMessage: nil) == "ok")
        #expect(DictationFileInject.reply(inserted: true, resultText: "\u{3000}fox", failureMessage: nil) == "ok")
        #expect(DictationFileInject.reply(inserted: true, resultText: " \t\n\r\u{00A0}", failureMessage: nil) == "ERROR nothing inserted")
        #expect(DictationFileInject.reply(inserted: true, resultText: "\u{00A0}quick brown fox\u{00A0}", failureMessage: nil) == "ok")
        #expect(DictationFileInject.reply(inserted: false, resultText: "\u{200B}", failureMessage: nil) == "ERROR nothing inserted")
        #expect(DictationFileInject.fieldMatches("\u{200B}hello", expected: "\u{200B}hello"))
        #expect(!DictationFileInject.fieldMatches("hello", expected: "\u{200B}hello"))
        #expect(DictationFileInject.fieldMatches("Hello there.", expected: " \u{00A0}hello\n"))
        #expect(!DictationFileInject.fieldMatches("hello", expected: " \t\n\r\u{00A0}"))
        #expect(DictationFileInject.fieldMatches("\u{000B}hello", expected: "\u{000B}hello"))
        #expect(DictationFileInject.fieldMatches("\u{3000}hello", expected: "\u{3000}hello"))
    }
}
