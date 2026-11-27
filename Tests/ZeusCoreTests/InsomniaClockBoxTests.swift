import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on an insomnia clock. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Insomnia clock box")
struct InsomniaClockBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(InsomniaClockBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(InsomniaClockBox.blankScalars.count == 5)
        #expect(InsomniaClockBox.blankScalars.contains(" "))
        #expect(InsomniaClockBox.blankScalars.contains("\t"))
        #expect(InsomniaClockBox.blankScalars.contains("\n"))
        #expect(InsomniaClockBox.blankScalars.contains("\r"))
        #expect(InsomniaClockBox.blankScalars.contains("\u{00A0}"))
        #expect(!InsomniaClockBox.blankScalars.contains("\u{200B}"))
        #expect(!InsomniaClockBox.blankScalars.contains("\u{000B}"))
        #expect(!InsomniaClockBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedClock() {
        #expect(InsomniaClockBox.trimmedClock("\u{200B}") == "\u{200B}")
        #expect(InsomniaClockBox.trimmedClock(" \u{200B} ") == "\u{200B}")
        #expect(InsomniaClockBox.trimmedClock("\t\u{200B}\n") == "\u{200B}")
        #expect(InsomniaClockBox.trimmedClock("\u{200B}23:30") == "\u{200B}23:30")
        #expect(InsomniaClockBox.trimmedClock("23:30\u{200B}") == "23:30\u{200B}")
        #expect(InsomniaClockBox.trimmedClock(" \t\n\r\u{00A0}") == "")
        #expect(InsomniaClockBox.trimmedClock("") == "")
        #expect(InsomniaClockBox.trimmedClock("\u{000B}23:30") == "\u{000B}23:30")
        #expect(InsomniaClockBox.trimmedClock("\u{3000}23:30") == "\u{3000}23:30")
        #expect(InsomniaClockBox.trimmedClock(" \t23:30\r\n") == "23:30")
        #expect(InsomniaClockBox.trimmedClock("\u{00A0}23:30\u{00A0}") == "23:30")
        #expect(InsomniaClockBox.trimmedClock("23:30") == "23:30")
    }

    @Test func aZeroWidthSpaceStaysOnTheClock() {
        #expect(InsomniaDuration.parseClock("\u{200B}23:30") == nil)
        #expect(InsomniaDuration.parseClock("23:30\u{200B}") == nil)
        #expect(InsomniaDuration.parseClock("\u{200B}") == nil)
        #expect(InsomniaDuration.parseClock(" \t\n\r\u{00A0}") == nil)
        #expect(InsomniaDuration.parseClock("\u{000B}23:30") == nil)
        #expect(InsomniaDuration.parseClock("\u{3000}23:30") == nil)
        #expect(InsomniaDuration.parseClock(" 23:30 ")! == (23, 30))
        #expect(InsomniaDuration.parseClock("\t7:05\n")! == (7, 5))
        #expect(InsomniaDuration.parseClock("\u{00A0}23:30\u{00A0}")! == (23, 30))
        #expect(InsomniaDuration.parseClock("\n23:30\r")! == (23, 30))
        #expect(InsomniaDuration.parseClock("23:30")! == (23, 30))
        #expect(InsomniaDuration.parseClock("7:05")! == (7, 5))
        #expect(InsomniaDuration.parseClock("24:00") == nil)
        #expect(InsomniaDuration.parseClock("7:5") == nil)
        #expect(InsomniaDuration.parseClock("soon") == nil)
    }
}
