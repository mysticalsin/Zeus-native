import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the number trim inside `ZeusTagParser.parseHighlight`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Highlight number box")
struct HighlightNumberBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(HighlightNumberBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(HighlightNumberBox.blankScalars.count == 5)
        #expect(HighlightNumberBox.blankScalars.contains(" "))
        #expect(HighlightNumberBox.blankScalars.contains("\t"))
        #expect(HighlightNumberBox.blankScalars.contains("\n"))
        #expect(HighlightNumberBox.blankScalars.contains("\r"))
        #expect(HighlightNumberBox.blankScalars.contains("\u{00A0}"))
        #expect(!HighlightNumberBox.blankScalars.contains("\u{200B}"))
        #expect(!HighlightNumberBox.blankScalars.contains("\u{000B}"))
        #expect(!HighlightNumberBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedNumber() {
        #expect(HighlightNumberBox.trimmedNumber("\u{200B}") == "\u{200B}")
        #expect(HighlightNumberBox.trimmedNumber(" \u{200B} ") == "\u{200B}")
        #expect(HighlightNumberBox.trimmedNumber("\t\u{200B}\n") == "\u{200B}")
        #expect(HighlightNumberBox.trimmedNumber("\u{200B}10") == "\u{200B}10")
        #expect(HighlightNumberBox.trimmedNumber("10\u{200B}") == "10\u{200B}")
        #expect(HighlightNumberBox.trimmedNumber("1\u{200B}0") == "1\u{200B}0")
        #expect(HighlightNumberBox.trimmedNumber(" \t\n\r\u{00A0}") == "")
        #expect(HighlightNumberBox.trimmedNumber("") == "")
        #expect(HighlightNumberBox.trimmedNumber("\u{000B}10") == "\u{000B}10")
        #expect(HighlightNumberBox.trimmedNumber("\u{3000}10") == "\u{3000}10")
        #expect(HighlightNumberBox.trimmedNumber(" \t10\r\n") == "10")
        #expect(HighlightNumberBox.trimmedNumber("\u{00A0}10\u{00A0}") == "10")
        #expect(HighlightNumberBox.trimmedNumber("10") == "10")
        #expect(HighlightNumberBox.trimmedNumber("\n") == "")
        #expect(HighlightNumberBox.trimmedNumber("\r") == "")
        #expect(HighlightNumberBox.trimmedNumber("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheNumberDecision() {
        let area = HighlightTarget(x: 10, y: 20, width: 300, height: 40)
        let toolbarNewline = HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar\n")
        #expect(tags("[HIGHLIGHT:10\u{200B},20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:10\u{200B},20,300,40]") != [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,\u{200B}20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:10,20\u{200B},300,40]") == [])
        #expect(tags("[HIGHLIGHT:10,20,300\u{200B},40]") == [])
        #expect(tags("[HIGHLIGHT:10,20,300,40\u{200B}]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{200B}10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,\u{3000}20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:10,\u{3000}20,300,40]") != [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,\n20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,\n20,300,40]") != [])
        #expect(tags("[HIGHLIGHT:10,\r20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\n10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40\n]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,\u{000B}20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:10,\u{000B}20,300,40]") != [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10, 20, 300, 40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\t10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT: \t10 , 20 , 300 , 40\t ]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{00A0}10,20,300,40\u{00A0}]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar\n]") == [.highlight(toolbarNewline)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar\n]") != [.highlight(HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar"))])
        #expect(spoken("[HIGHLIGHT:10\u{200B},20,300,40] that's the toolbar") == "that's the toolbar")
        #expect(tags("[HIGHLIGHT:10\u{200B},20,300,40] that's the toolbar") == [])
    }

    private func tags(_ reply: String) -> [ZeusTag] {
        ZeusTagParser.parse(reply).tags
    }

    private func spoken(_ reply: String) -> String {
        ZeusTagParser.parse(reply).spokenText
    }
}
