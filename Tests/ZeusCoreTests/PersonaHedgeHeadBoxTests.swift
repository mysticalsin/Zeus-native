import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the head trim inside `PersonaCompliance.strip(hedgeIn:)`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
/// The sentence trim in that function still uses `CharacterSet.whitespacesAndNewlines`.
/// The punctuation trim in that function still uses `CharacterSet.whitespaces`.
@Suite("Persona hedge head box")
struct PersonaHedgeHeadBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PersonaHedgeHeadBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PersonaHedgeHeadBox.blankScalars.count == 5)
        #expect(PersonaHedgeHeadBox.blankScalars.contains(" "))
        #expect(PersonaHedgeHeadBox.blankScalars.contains("\t"))
        #expect(PersonaHedgeHeadBox.blankScalars.contains("\n"))
        #expect(PersonaHedgeHeadBox.blankScalars.contains("\r"))
        #expect(PersonaHedgeHeadBox.blankScalars.contains("\u{00A0}"))
        #expect(!PersonaHedgeHeadBox.blankScalars.contains("\u{200B}"))
        #expect(!PersonaHedgeHeadBox.blankScalars.contains("\u{000B}"))
        #expect(!PersonaHedgeHeadBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedHead() {
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{200B}") == "\u{200B}")
        #expect(PersonaHedgeHeadBox.trimmedHead(" \u{200B} ") == "\u{200B}")
        #expect(PersonaHedgeHeadBox.trimmedHead("\t\u{200B}\n") == "\u{200B}")
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{200B}Quiet") == "\u{200B}Quiet")
        #expect(PersonaHedgeHeadBox.trimmedHead("Quiet\u{200B}") == "Quiet\u{200B}")
        #expect(PersonaHedgeHeadBox.trimmedHead(" \t\n\r\u{00A0}") == "")
        #expect(PersonaHedgeHeadBox.trimmedHead("") == "")
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{000B}") == "\u{000B}")
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{3000}") == "\u{3000}")
        #expect(PersonaHedgeHeadBox.trimmedHead(" \tQuiet\r\n") == "Quiet")
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{00A0}Quiet\u{00A0}") == "Quiet")
        #expect(PersonaHedgeHeadBox.trimmedHead("Quiet") == "Quiet")
        #expect(PersonaHedgeHeadBox.trimmedHead("Q\u{200B}uiet") == "Q\u{200B}uiet")
        #expect(PersonaHedgeHeadBox.trimmedHead("\n") == "")
        #expect(PersonaHedgeHeadBox.trimmedHead("\r") == "")
        #expect(PersonaHedgeHeadBox.trimmedHead("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysWhenTheHedgeHeadIsTrimmed() {
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{200B}") == "\u{200B}")
        #expect(!PersonaHedgeHeadBox.trimmedHead("\u{200B}").isEmpty)
        #expect(PersonaHedgeHeadBox.trimmedHead("\u{3000}").isEmpty == false)
        #expect(PersonaHedgeHeadBox.trimmedHead("\n").isEmpty)
        #expect(PersonaHedgeHeadBox.trimmedHead("\r").isEmpty)
        #expect(PersonaHedgeHeadBox.trimmedHead(" \t\n\r\u{00A0}").isEmpty)
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, FOR NOW.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Operational. The machines are behaving, for now.")
                == "Operational. The machines are behaving.")
        #expect(PersonaCompliance.stripOminousHedges("All is calm for the moment!") == "All is calm!")
        #expect(PersonaCompliance.stripOminousHedges("Stable, for the time being") == "Stable.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet\u{200B}, for now.") == "Quiet\u{200B}.")
        #expect(PersonaCompliance.stripOminousHedges("\u{200B}Quiet, for now.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("\u{200B}, for now.") == "\u{200B}, for now.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now.\u{200B}") == "Quiet.\u{200B}")
        #expect(PersonaCompliance.stripOminousHedges("Fine.") == "Fine.")
        #expect(PersonaCompliance.stripOminousHedges("For now is a phrase.") == "For now is a phrase.")
        #expect(PersonaCompliance.hasOminousHedge("Fine, for now."))
        #expect(!PersonaCompliance.hasOminousHedge("Fine."))
        #expect(PersonaCompliance.hasOminousHedge("Quiet\u{200B}, for now."))
        #expect(!PersonaCompliance.hasOminousHedge("\u{200B}, for now."))
    }
}
