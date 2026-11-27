import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a spoken failure. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Spoken failure box")
struct SpokenFailureBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(SpokenFailureBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(SpokenFailureBox.blankScalars.count == 5)
        #expect(SpokenFailureBox.blankScalars.contains(" "))
        #expect(SpokenFailureBox.blankScalars.contains("\t"))
        #expect(SpokenFailureBox.blankScalars.contains("\n"))
        #expect(SpokenFailureBox.blankScalars.contains("\r"))
        #expect(SpokenFailureBox.blankScalars.contains("\u{00A0}"))
        #expect(!SpokenFailureBox.blankScalars.contains("\u{200B}"))
        #expect(!SpokenFailureBox.blankScalars.contains("\u{000B}"))
        #expect(!SpokenFailureBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInAFoldedLine() {
        #expect(SpokenFailureBox.folded("\u{200B}") == "\u{200B}")
        #expect(SpokenFailureBox.folded(" \u{200B} ") == "\u{200B}")
        #expect(SpokenFailureBox.folded("\t\u{200B}\n") == "\u{200B}")
        #expect(SpokenFailureBox.folded("\u{200B}Try again") == "\u{200B}Try again")
        #expect(SpokenFailureBox.folded("Try again\u{200B}") == "Try again\u{200B}")
        #expect(SpokenFailureBox.folded(" \t\n\r\u{00A0}") == "")
        #expect(SpokenFailureBox.folded("\u{000B}Tony") == "\u{000B}Tony")
        #expect(SpokenFailureBox.folded("\u{3000}Tony") == "\u{3000}Tony")
        #expect(SpokenFailureBox.folded(" \tTony\r\n") == "Tony")
        #expect(SpokenFailureBox.folded("\u{00A0}Tony\u{00A0}") == "Tony")
        #expect(SpokenFailureBox.folded("a\u{00A0}\u{00A0}b") == "a b")
        #expect(SpokenFailureBox.folded("one\ntwo") == "one two")
    }

    @Test func aZeroWidthSpaceIsSpokenInsteadOfTheErrorBank() {
        let bank = Set(ZeusVoiceLines.bank(.ultron)[.errorSpoken] ?? [])
            .union(ZeusVoiceLines.bank(.plain)[.errorSpoken] ?? [])
        #expect(SpokenFailure.line("\u{200B}") == "\u{200B}")
        #expect(SpokenFailure.line(" \u{200B} ") == "\u{200B}")
        #expect(SpokenFailure.line("\u{200B}Try again") == "\u{200B}Try again")
        #expect(SpokenFailure.line("\u{000B}") == "\u{000B}")
        #expect(SpokenFailure.line("\u{3000}kept") == "\u{3000}kept")
        #expect(bank.contains(SpokenFailure.line(" \t\n\r\u{00A0}")))
        #expect(bank.contains(SpokenFailure.line("")))
        #expect(SpokenFailure.line("  You've hit your weekly limit  ") == "Every AI is out of quota.")
        #expect(bank.contains(SpokenFailure.line("HTTP 500 traceback in the provider")))
        #expect(SpokenFailure.line("one two three four five six seven eight nine ten eleven")
            == "one two three four five six seven eight nine ten.")
        #expect(SpokenFailure.line("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven")
            == "one two three four five six seven eight nine ten.")
    }
}
