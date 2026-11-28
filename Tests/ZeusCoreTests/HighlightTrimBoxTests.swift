import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the highlight trim inside `ZeusTagParser.parseHighlight`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Highlight trim box")
struct HighlightTrimBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(HighlightTrimBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(HighlightTrimBox.blankScalars.count == 5)
        #expect(HighlightTrimBox.blankScalars.contains(" "))
        #expect(HighlightTrimBox.blankScalars.contains("\t"))
        #expect(HighlightTrimBox.blankScalars.contains("\n"))
        #expect(HighlightTrimBox.blankScalars.contains("\r"))
        #expect(HighlightTrimBox.blankScalars.contains("\u{00A0}"))
        #expect(!HighlightTrimBox.blankScalars.contains("\u{200B}"))
        #expect(!HighlightTrimBox.blankScalars.contains("\u{000B}"))
        #expect(!HighlightTrimBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedHighlight() {
        #expect(HighlightTrimBox.trimmedHighlight("\u{200B}") == "\u{200B}")
        #expect(HighlightTrimBox.trimmedHighlight(" \u{200B} ") == "\u{200B}")
        #expect(HighlightTrimBox.trimmedHighlight("\t\u{200B}\n") == "\u{200B}")
        #expect(HighlightTrimBox.trimmedHighlight("\u{200B}10,20,300,40") == "\u{200B}10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("10,20,300,40\u{200B}") == "10,20,300,40\u{200B}")
        #expect(HighlightTrimBox.trimmedHighlight(" \t\n\r\u{00A0}") == "")
        #expect(HighlightTrimBox.trimmedHighlight("") == "")
        #expect(HighlightTrimBox.trimmedHighlight("\u{000B}10,20,300,40") == "\u{000B}10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("\u{3000}10,20,300,40") == "\u{3000}10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight(" \t10,20,300,40\r\n") == "10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("\u{00A0}10,20,300,40\u{00A0}") == "10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("10,20,300,40") == "10,20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("10,\u{200B}20,300,40") == "10,\u{200B}20,300,40")
        #expect(HighlightTrimBox.trimmedHighlight("\n") == "")
        #expect(HighlightTrimBox.trimmedHighlight("\r") == "")
        #expect(HighlightTrimBox.trimmedHighlight("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheHighlightDecision() {
        let area = HighlightTarget(x: 10, y: 20, width: 300, height: 40)
        let toolbar = HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar")
        let toolbarScreen = HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar", screen: 2)
        let screenOnly = HighlightTarget(x: 10, y: 20, width: 300, height: 40, screen: 2)
        #expect(tags("[HIGHLIGHT:\n10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\n10,20,300,40]") != [])
        #expect(tags("[HIGHLIGHT:\r10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40\n]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40\r]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\n\u{200B}10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\n\u{200B}10,20,300,40]") != [])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar\n]") == [.highlight(toolbar)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar\n]") != [.highlight(HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "toolbar\n"))])
        #expect(tags("[HIGHLIGHT:10,20,300,40:screen2\n]") == [.highlight(screenOnly)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:screen2\n]") != [.highlight(HighlightTarget(x: 10, y: 20, width: 300, height: 40, label: "screen2\n"))])
        #expect(tags("[HIGHLIGHT:\n10,20,300,40:toolbar:screen2]") == [.highlight(toolbarScreen)])
        #expect(tags("[HIGHLIGHT:\u{200B}10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40\u{200B}]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{3000}10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{000B}10,20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:\u{000B}10,20,300,40]") != [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{200B}\n10,20,300,40]") == [])
        #expect(tags("[HIGHLIGHT:\u{200B}\n10,20,300,40]") != [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10, 20, 300, 40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\t10,20,300,40]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT: \t10 , 20 , 300 , 40\t ]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\u{00A0}10,20,300,40\u{00A0}]") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar]") == [.highlight(toolbar)])
        #expect(tags("[HIGHLIGHT:10,20,300,40:toolbar:screen2]") == [.highlight(toolbarScreen)])
        #expect(spoken("[HIGHLIGHT:\n10,20,300,40] that's the toolbar") == "that's the toolbar")
        #expect(tags("[HIGHLIGHT:\n10,20,300,40] that's the toolbar") == [.highlight(area)])
        #expect(tags("[HIGHLIGHT:\n10,20,300,40] that's the toolbar") != [])
    }

    private func tags(_ reply: String) -> [ZeusTag] {
        ZeusTagParser.parse(reply).tags
    }

    private func spoken(_ reply: String) -> String {
        ZeusTagParser.parse(reply).spokenText
    }
}
