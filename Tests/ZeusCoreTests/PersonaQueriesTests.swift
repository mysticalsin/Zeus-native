import Testing
import ZeusCore

@Suite struct PersonaQueriesTests {
    @Test func explicitPersonalityUsesAnIndependentLineBank() {
        let plain = PersonaQueries.localAnswer(for: "who are you", personality: .plain, lines: ZeusVoiceLines(pick: { _ in 0 }))
        let ultron = PersonaQueries.localAnswer(for: "who are you", personality: .ultron, lines: ZeusVoiceLines(pick: { _ in 0 }))
        #expect(plain == "I'm Zeus, your Mac assistant.")
        #expect(ultron == "Zeus. Synthetic mind on your Mac.")
    }

    @Test func whoAreYouUsesThePersonaBank() {
        let answer = PersonaQueries.localAnswer(for: "who are you", personality: .ultron)
        #expect(answer != nil)
        #expect(!answer!.isEmpty)
        #expect(!answer!.lowercased().contains("terminal tasks"))
        #expect(!answer!.lowercased().contains("yours to command"))
        #expect(!answer!.lowercased().contains("loyal"))
    }

    @Test func capabilitiesStayLocal() {
        #expect(PersonaQueries.localAnswer(for: "what can you do", personality: .ultron) != nil)
    }

    @Test func simpleMultiplicationStaysLocal() {
        #expect(PersonaQueries.localAnswer(for: "what is 17 times 23", personality: .ultron) == "391.")
    }

    @Test func unrelatedQuestionsStayOnTheBrain() {
        #expect(PersonaQueries.localAnswer(for: "open Spotify", personality: .ultron) == nil)
    }

    @Test func jokeUsesThePersonaBankNotAStockPunchline() {
        let answer = PersonaQueries.localAnswer(for: "tell me a joke", personality: .ultron)
        #expect(answer != nil)
        #expect(!answer!.lowercased().contains("why did the"))
        #expect(!answer!.lowercased().contains("therapy"))
    }

    @Test func australiaCapitalIsResultFirst() {
        let answer = PersonaQueries.localAnswer(for: "what is the capital of australia", personality: .ultron)
        #expect(answer?.hasPrefix("Canberra") == true)
    }
}
