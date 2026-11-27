import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a screenshot filename. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Screenshot filename box")
struct ScreenshotFilenameBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScreenshotFilenameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScreenshotFilenameBox.blankScalars.count == 5)
        #expect(ScreenshotFilenameBox.blankScalars.contains(" "))
        #expect(ScreenshotFilenameBox.blankScalars.contains("\t"))
        #expect(ScreenshotFilenameBox.blankScalars.contains("\n"))
        #expect(ScreenshotFilenameBox.blankScalars.contains("\r"))
        #expect(ScreenshotFilenameBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScreenshotFilenameBox.blankScalars.contains("\u{200B}"))
        #expect(!ScreenshotFilenameBox.blankScalars.contains("\u{000B}"))
        #expect(!ScreenshotFilenameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedName() {
        #expect(ScreenshotFilenameBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(ScreenshotFilenameBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(ScreenshotFilenameBox.trimmedName("\t\u{200B}\n") == "\u{200B}")
        #expect(ScreenshotFilenameBox.trimmedName("\u{200B}Screenshot.png") == "\u{200B}Screenshot.png")
        #expect(ScreenshotFilenameBox.trimmedName("Screenshot.png\u{200B}") == "Screenshot.png\u{200B}")
        #expect(ScreenshotFilenameBox.trimmedName(" \t\n\r\u{00A0}") == "")
        #expect(ScreenshotFilenameBox.trimmedName("") == "")
        #expect(ScreenshotFilenameBox.trimmedName("\u{000B}Screenshot.png") == "\u{000B}Screenshot.png")
        #expect(ScreenshotFilenameBox.trimmedName("\u{3000}Screenshot.png") == "\u{3000}Screenshot.png")
        #expect(ScreenshotFilenameBox.trimmedName(" \tScreenshot.png\r\n") == "Screenshot.png")
        #expect(ScreenshotFilenameBox.trimmedName("\u{00A0}Screenshot.png\u{00A0}") == "Screenshot.png")
        #expect(ScreenshotFilenameBox.trimmedName("Screen\u{00A0}Shot.png") == "Screen\u{00A0}Shot.png")
    }

    @Test func aZeroWidthSpaceDoesNotCountAsAScreenshot() {
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "\u{200B}Screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.png\u{200B}"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: " \u{200B}Screenshot.png "))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "  SCREENSHOT.PNG  "))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "\nScreen Shot.JPEG\t"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "\u{00A0}Screenshot.png\u{00A0}"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "\u{000B}Screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "\u{3000}Screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "   "))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: " \t\n\r\u{00A0}"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "\u{200B}"))
        #expect(ScreenshotDetectorBox.isScreenshot(filename: "Screenshot.png"))
        #expect(!ScreenshotDetectorBox.isScreenshot(filename: "  notes.PNG  "))
    }
}
