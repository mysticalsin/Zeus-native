import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a compliance sentence. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Persona compliance box")
struct PersonaComplianceBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PersonaComplianceBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PersonaComplianceBox.blankScalars.count == 5)
        #expect(PersonaComplianceBox.blankScalars.contains(" "))
        #expect(PersonaComplianceBox.blankScalars.contains("\t"))
        #expect(PersonaComplianceBox.blankScalars.contains("\n"))
        #expect(PersonaComplianceBox.blankScalars.contains("\r"))
        #expect(PersonaComplianceBox.blankScalars.contains("\u{00A0}"))
        #expect(!PersonaComplianceBox.blankScalars.contains("\u{200B}"))
        #expect(!PersonaComplianceBox.blankScalars.contains("\u{000B}"))
        #expect(!PersonaComplianceBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATrimmedSentence() {
        #expect(PersonaComplianceBox.trimmedSentence("\u{200B}") == "\u{200B}")
        #expect(PersonaComplianceBox.trimmedSentence(" \u{200B} ") == "\u{200B}")
        #expect(PersonaComplianceBox.trimmedSentence("\t\u{200B}\n") == "\u{200B}")
        #expect(PersonaComplianceBox.trimmedSentence("\u{200B}Behaving") == "\u{200B}Behaving")
        #expect(PersonaComplianceBox.trimmedSentence("Behaving\u{200B}") == "Behaving\u{200B}")
        #expect(PersonaComplianceBox.trimmedSentence(" \t\n\r\u{00A0}") == "")
        #expect(PersonaComplianceBox.trimmedSentence("") == "")
        #expect(PersonaComplianceBox.trimmedSentence("\u{000B}Behaving") == "\u{000B}Behaving")
        #expect(PersonaComplianceBox.trimmedSentence("\u{3000}Behaving") == "\u{3000}Behaving")
        #expect(PersonaComplianceBox.trimmedSentence(" \tBehaving\r\n") == "Behaving")
        #expect(PersonaComplianceBox.trimmedSentence("\u{00A0}Behaving\u{00A0}") == "Behaving")
        #expect(PersonaComplianceBox.trimmedSentence("a\u{00A0}b") == "a\u{00A0}b")
    }

    @Test func aZeroWidthSpaceStaysWhenAHedgeIsRemoved() {
        #expect(PersonaCompliance.stripOminousHedges("\u{200B}The machines are behaving, for now.")
                == "\u{200B}The machines are behaving.")
        #expect(PersonaCompliance.stripOminousHedges(" \u{200B}Quiet, for now. ")
                == "\u{200B}Quiet. ")
        #expect(PersonaCompliance.stripOminousHedges("\u{000B}Stable, for the time being")
                == "\u{000B}Stable.")
        #expect(PersonaCompliance.stripOminousHedges("\u{3000}All is calm for the moment!")
                == "\u{3000}All is calm!")
        #expect(PersonaCompliance.stripOminousHedges("\u{00A0}Quiet, FOR NOW.\u{00A0}")
                == "Quiet.\u{00A0}")
        #expect(PersonaCompliance.stripOminousHedges(" \t\n\r\u{00A0}") == " \t\n\r\u{00A0}")
        #expect(PersonaCompliance.stripOminousHedges("\u{200B}") == "\u{200B}")
        #expect(!PersonaCompliance.hasOminousHedge("\u{200B}"))
        #expect(PersonaCompliance.hasOminousHedge("\u{200B}Fine, for now."))
        #expect(PersonaCompliance.stripOminousHedges("Operational. The machines are behaving, for now.")
                == "Operational. The machines are behaving.")
        #expect(PersonaCompliance.stripOminousHedges("All is calm for the moment!") == "All is calm!")
        #expect(PersonaCompliance.stripOminousHedges("Stable, for the time being") == "Stable.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, FOR NOW.") == "Quiet.")
        #expect(PersonaCompliance.stripOminousHedges("For now is a phrase.") == "For now is a phrase.")
        #expect(!PersonaCompliance.hasOminousHedge("Fine."))
        #expect(PersonaCompliance.hasOminousHedge("Fine, for now."))
    }
}
