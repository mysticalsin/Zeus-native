import Testing
import ZeusCore

@Suite struct PersonaQueriesTests {
    @Test func whoAreYouUsesThePersonaBank() {
        let answer = PersonaQueries.localAnswer(for: "who are you")
        #expect(answer != nil)
        #expect(!answer!.isEmpty)
        #expect(!answer!.lowercased().contains("terminal tasks"))
        #expect(!answer!.lowercased().contains("yours to command"))
        #expect(!answer!.lowercased().contains("loyal"))
    }

    @Test func capabilitiesStayLocal() {
        #expect(PersonaQueries.localAnswer(for: "what can you do") != nil)
    }

    @Test func simpleMultiplicationStaysLocal() {
        #expect(PersonaQueries.localAnswer(for: "what is 17 times 23") == "391.")
    }

    @Test func unrelatedQuestionsStayOnTheBrain() {
        #expect(PersonaQueries.localAnswer(for: "open Spotify") == nil)
    }

    @Test func jokeUsesThePersonaBankNotAStockPunchline() {
        let answer = PersonaQueries.localAnswer(for: "tell me a joke")
        #expect(answer != nil)
        #expect(!answer!.lowercased().contains("why did the"))
        #expect(!answer!.lowercased().contains("therapy"))
    }

    @Test func australiaCapitalIsResultFirst() {
        let answer = PersonaQueries.localAnswer(for: "what is the capital of australia")
        #expect(answer?.hasPrefix("Canberra") == true)
    }
}
