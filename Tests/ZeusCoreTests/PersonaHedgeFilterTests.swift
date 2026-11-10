import Testing
@testable import ZeusCore

@Suite("Persona hedge filter")
struct PersonaHedgeFilterTests {
    @Test func stripsTrailingForNow() {
        #expect(PersonaCompliance.stripOminousHedges("Operational. The machines are behaving, for now.")
                == "Operational. The machines are behaving.")
        #expect(PersonaCompliance.stripOminousHedges("All is calm for the moment!") == "All is calm!")
        #expect(PersonaCompliance.stripOminousHedges("Stable, for the time being") == "Stable.")
        #expect(PersonaCompliance.stripOminousHedges("Quiet, FOR NOW.") == "Quiet.")
    }

    @Test func leavesOtherTextAlone() {
        for text in ["Operational.", "For now is a phrase.", "Do it now.", "Wait until noon.", "It works for nowhere.", ""] {
            #expect(PersonaCompliance.stripOminousHedges(text) == text, "\(text)")
        }
    }

    @Test func detectsHedges() {
        #expect(PersonaCompliance.hasOminousHedge("Fine, for now."))
        #expect(!PersonaCompliance.hasOminousHedge("Fine."))
    }
}
