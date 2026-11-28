import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the punctuation trim inside `PersonaCompliance.strip(hedgeIn:)`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
/// The sentence trim in that function still uses `CharacterSet.whitespacesAndNewlines`.
/// The head trim in that function still uses `CharacterSet.whitespaces`.
@Suite("Persona hedge punctuation box")
struct PersonaHedgePunctuationBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PersonaHedgePunctuationBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PersonaHedgePunctuationBox.blankScalars.count == 5)
        #expect(PersonaHedgePunctuationBox.blankScalars.contains(" "))
        #expect(PersonaHedgePunctuationBox.blankScalars.contains("\t"))
        #expect(PersonaHedgePunctuationBox.blankScalars.contains("\n"))
        #expect(PersonaHedgePunctuationBox.blankScalars.contains("\r"))
        #expect(PersonaHedgePunctuationBox.blankScalars.contains("\u{00A0}"))
        #expect(!PersonaHedgePunctuationBox.blankScalars.contains("\u{200B}"))
        #expect(!PersonaHedgePunctuationBox.blankScalars.contains("\u{000B}"))
        #expect(!PersonaHedgePunctuationBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPunctuation() {
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{200B}") == "\u{200B}")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(" \u{200B} ") == "\u{200B}")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\t\u{200B}\n") == "\u{200B}")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{200B}.") == "\u{200B}.")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(".\u{200B}") == ".\u{200B}")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(" \t\n\r\u{00A0}") == "")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("") == "")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{000B}.") == "\u{000B}.")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{3000}.") == "\u{3000}.")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(" \t.\r\n") == ".")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{00A0}.\u{00A0}") == ".")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(".") == ".")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation(".\u{200B}!") == ".\u{200B}!")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\n.") == ".")
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\r.") == ".")
    }

    @Test func aZeroWidthSpaceStaysWhenHedgePunctuationIsTrimmed() {
        #expect(PersonaHedgePunctuationBox.trimmedPunctuation("\u{200B}") == "\u{200B}")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, FOR NOW.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Operational. The machines are behaving, for now.")
                == "Operational. The machines are behaving.")
        #expect(PersonaCompliance.stripOminousHedges("All is calm for the moment!") == "All is calm!")
        #expect(PersonaCompliance.stripOminousHedges("Stable, for the time being") == "Stable.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now\u{3000}.") == "Quiet\u{3000}.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now\n.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now\r.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now\u{00A0}.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now\u{000B}.") == "Quiet\u{000B}.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet\u{200B}, for now.") == "Quiet\u{200B}.")
        #expect(PersonaCompliance.stripOminousHedges("\u{200B}Quiet, for now.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, for now.\u{200B}") == "Quiet.\u{200B}")
        #expect(PersonaCompliance.stripOminousHedges("Fine.") == "Fine.")
        #expect(PersonaCompliance.stripOminousHedges("For now is a phrase.") == "For now is a phrase.")
        #expect(PersonaCompliance.hasOminousHedge("Fine, for now."))
        #expect(!PersonaCompliance.hasOminousHedge("Fine."))
        #expect(PersonaCompliance.hasOminousHedge("Quiet, for now\u{3000}."))
        #expect(PersonaCompliance.hasOminousHedge("Quiet, for now\n."))
    }
}
