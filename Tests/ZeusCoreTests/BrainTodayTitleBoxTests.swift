import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the title trim inside `BrainToday.clean`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Brain today title box")
struct BrainTodayTitleBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BrainTodayTitleBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BrainTodayTitleBox.blankScalars.count == 5)
        #expect(BrainTodayTitleBox.blankScalars.contains(" "))
        #expect(BrainTodayTitleBox.blankScalars.contains("\t"))
        #expect(BrainTodayTitleBox.blankScalars.contains("\n"))
        #expect(BrainTodayTitleBox.blankScalars.contains("\r"))
        #expect(BrainTodayTitleBox.blankScalars.contains("\u{00A0}"))
        #expect(!BrainTodayTitleBox.blankScalars.contains("\u{200B}"))
        #expect(!BrainTodayTitleBox.blankScalars.contains("\u{000B}"))
        #expect(!BrainTodayTitleBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedTitle() {
        #expect(BrainTodayTitleBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(BrainTodayTitleBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(BrainTodayTitleBox.trimmedTitle("\t\u{200B}\n") == "\u{200B}")
        #expect(BrainTodayTitleBox.trimmedTitle("\u{200B}Call") == "\u{200B}Call")
        #expect(BrainTodayTitleBox.trimmedTitle("Call\u{200B}") == "Call\u{200B}")
        #expect(BrainTodayTitleBox.trimmedTitle(" \t\n\r\u{00A0}") == "")
        #expect(BrainTodayTitleBox.trimmedTitle("") == "")
        #expect(BrainTodayTitleBox.trimmedTitle("\u{000B}Call") == "\u{000B}Call")
        #expect(BrainTodayTitleBox.trimmedTitle("\u{3000}Call") == "\u{3000}Call")
        #expect(BrainTodayTitleBox.trimmedTitle(" \tCall\r\n") == "Call")
        #expect(BrainTodayTitleBox.trimmedTitle("\u{00A0}Call\u{00A0}") == "Call")
        #expect(BrainTodayTitleBox.trimmedTitle("Call") == "Call")
        #expect(BrainTodayTitleBox.trimmedTitle("Ca\u{200B}ll") == "Ca\u{200B}ll")
        #expect(BrainTodayTitleBox.trimmedTitle("\n") == "")
        #expect(BrainTodayTitleBox.trimmedTitle("\r") == "")
        #expect(BrainTodayTitleBox.trimmedTitle("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheCleanedTitle() {
        #expect(BrainToday.clean("\u{200B}") == "\u{200B}")
        #expect(BrainToday.clean(" \u{200B} ") == "\u{200B}")
        #expect(BrainToday.clean("\t\u{200B}\n") == "\u{200B}")
        #expect(BrainToday.clean("\n\u{200B}\r") == "\u{200B}")
        #expect(BrainToday.clean("\u{200B}Call Anna") == "\u{200B}Call Anna")
        #expect(BrainToday.clean("Call Anna\u{200B}") == "Call Anna\u{200B}")
        #expect(BrainToday.clean("Call\u{200B}Anna") == "Call\u{200B}Anna")
        #expect(BrainToday.clean("\u{3000}") == "\u{3000}")
        #expect(BrainToday.clean("\u{3000}Call Anna") == "\u{3000}Call Anna")
        #expect(BrainToday.clean("\u{000B}") == "\u{000B}")
        #expect(BrainToday.clean("\u{000B}Call Anna") == "\u{000B}Call Anna")
        #expect(BrainToday.clean(" \tCall Anna\r\n") == "Call Anna")
        #expect(BrainToday.clean("\u{00A0}Call Anna\u{00A0}") == "Call Anna")
        #expect(BrainToday.clean("Call Anna") == "Call Anna")
        #expect(BrainToday.clean("TASK-0001 Low thing #todo #priority/low") == "Low thing")
        #expect(BrainToday.clean("Call Anna 📅 2026-10-31") == "Call Anna")
        #expect(BrainToday.clean("  [[Soul]]  ") == "Soul")
        #expect(BrainToday.clean("[[So\u{200B}ul]]") == "So\u{200B}ul")
        #expect(BrainToday.clean("\u{200B}Call #today") == "\u{200B}Call")
        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}", "  "] {
            #expect(BrainToday.clean(blank) == "")
        }
    }
}
