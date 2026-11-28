import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a screen-corner size label. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Screen corner label box")
struct ScreenCornerLabelBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScreenCornerLabelBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScreenCornerLabelBox.blankScalars.count == 5)
        #expect(ScreenCornerLabelBox.blankScalars.contains(" "))
        #expect(ScreenCornerLabelBox.blankScalars.contains("\t"))
        #expect(ScreenCornerLabelBox.blankScalars.contains("\n"))
        #expect(ScreenCornerLabelBox.blankScalars.contains("\r"))
        #expect(ScreenCornerLabelBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScreenCornerLabelBox.blankScalars.contains("\u{200B}"))
        #expect(!ScreenCornerLabelBox.blankScalars.contains("\u{000B}"))
        #expect(!ScreenCornerLabelBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedLabel() {
        #expect(ScreenCornerLabelBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(ScreenCornerLabelBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(ScreenCornerLabelBox.trimmedLabel("\t\u{200B}\n") == "\u{200B}")
        #expect(ScreenCornerLabelBox.trimmedLabel("\u{200B}Small") == "\u{200B}Small")
        #expect(ScreenCornerLabelBox.trimmedLabel("Large\u{200B}") == "Large\u{200B}")
        #expect(ScreenCornerLabelBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(ScreenCornerLabelBox.trimmedLabel("") == "")
        #expect(ScreenCornerLabelBox.trimmedLabel("\u{000B}Small") == "\u{000B}Small")
        #expect(ScreenCornerLabelBox.trimmedLabel("\u{3000}Small") == "\u{3000}Small")
        #expect(ScreenCornerLabelBox.trimmedLabel(" \tLarge\r\n") == "Large")
        #expect(ScreenCornerLabelBox.trimmedLabel("\u{00A0}Medium\u{00A0}") == "Medium")
        #expect(ScreenCornerLabelBox.trimmedLabel("Small") == "Small")
    }

    @Test func aZeroWidthSpaceStaysOnTheCornerSizeLabel() {
        #expect(ScreenCornerLabelBox.trimmedLabel(" \u{200B}Large") == "\u{200B}Large")
        #expect(ScreenCornerLabelBox.trimmedLabel(" Large") == "Large")
        #expect(ScreenCornerLabelBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(ScreenCornerSize(label: "\u{200B}") == .medium)
        #expect(ScreenCornerSize(label: "\u{200B}Small") == .medium)
        #expect(ScreenCornerSize(label: " large ") == .large)
        #expect(ScreenCornerSize(label: "SMALL") == .small)
        #expect(ScreenCornerSize(label: "\u{00A0}Medium\u{00A0}") == .medium)
        #expect(ScreenCornerSize(label: "\u{3000}Small") == .medium)
        #expect(ScreenCornerSize(label: "\u{000B}Large") == .medium)
        #expect(ScreenCornerSize(label: "\nLarge\n") == .large)
        #expect(ScreenCornerSize(label: "") == .medium)
    }
}
