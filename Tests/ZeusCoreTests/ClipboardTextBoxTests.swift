import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in clipboard text. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Clipboard text box")
struct ClipboardTextBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ClipboardTextBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ClipboardTextBox.blankScalars.count == 5)
        #expect(ClipboardTextBox.blankScalars.contains(" "))
        #expect(ClipboardTextBox.blankScalars.contains("\t"))
        #expect(ClipboardTextBox.blankScalars.contains("\n"))
        #expect(ClipboardTextBox.blankScalars.contains("\r"))
        #expect(ClipboardTextBox.blankScalars.contains("\u{00A0}"))
        #expect(!ClipboardTextBox.blankScalars.contains("\u{200B}"))
        #expect(!ClipboardTextBox.blankScalars.contains("\u{000B}"))
        #expect(!ClipboardTextBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTrimmedText() {
        #expect(ClipboardTextBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(ClipboardTextBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(ClipboardTextBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(ClipboardTextBox.trimmedText("\u{200B}hello") == "\u{200B}hello")
        #expect(ClipboardTextBox.trimmedText("hello\u{200B}") == "hello\u{200B}")
        #expect(ClipboardTextBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(ClipboardTextBox.trimmedText("") == "")
        #expect(ClipboardTextBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(ClipboardTextBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(ClipboardTextBox.trimmedText(" \thello\r\n") == "hello")
        #expect(ClipboardTextBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ClipboardTextBox.trimmedText("hello\u{00A0}there") == "hello\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInTheClipboardChecks() {
        let zwsp = "\u{200B}"
        #expect(ClipboardHistoryBox.canAddText(zwsp))
        #expect(ClipboardHistoryBox.canAddText(" \(zwsp) "))
        #expect(!ClipboardHistoryBox.canAddText(" \t\n\r\u{00A0}"))
        #expect(!ClipboardHistoryBox.canAddText(""))
        #expect(ClipboardHistoryBox.canAddText("\u{000B}"))
        #expect(ClipboardHistoryBox.canAddText("\u{3000}"))
        #expect(ClipboardHistoryBox.preview(zwsp) == zwsp)
        #expect(ClipboardHistoryBox.preview(" \(zwsp) ") == zwsp)
        #expect(ClipboardHistoryBox.preview("\u{3000}hello") == "\u{3000}hello")
        #expect(ClipboardHistoryBox.preview(" \thello\r\n") == "hello")
        #expect(ClipboardHistoryBox.preview("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ClipboardHistoryBox.isLink("\u{00A0}https://example.com\u{00A0}"))
        #expect(!ClipboardHistoryBox.isLink(zwsp))
        #expect(ClipboardHistoryBox.normalizedSearch(zwsp) == zwsp)
        #expect(ClipboardHistoryBox.normalizedSearch(" \(zwsp) ") == zwsp)
        #expect(ClipboardHistoryBox.normalizedSearch(" \t\n\r\u{00A0}") == "")
        #expect(ClipboardHistoryBox.normalizedSearch("\u{000B}hello") == "\u{000B}hello")
        #expect(ClipboardHistoryBox.normalizedSearch("\u{3000}hello") == "\u{3000}hello")
        #expect(ClipboardHistoryBox.normalizedSearch("  Hello  ") == "Hello")
        var history = ClipboardHistory(limit: 60)
        let added = history.add(zwsp)
        #expect(added)
        #expect(history.entries.map(\.text) == [zwsp])
        let rejected = history.add(" \t\n\r\u{00A0}")
        #expect(rejected == false)
        #expect(history.entries.map(\.text) == [zwsp])
    }
}
