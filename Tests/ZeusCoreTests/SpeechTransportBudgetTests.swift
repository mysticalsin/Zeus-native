import Testing
@testable import ZeusCore

@Suite("Speech transport budget")
struct SpeechTransportBudgetTests {
    @Test func resourceCapMatchesTheRequestTimeout() {
        #expect(SpeechTransportBudget.resourceTimeout(request: 20) == 20)
        #expect(SpeechTransportBudget.resourceTimeout(request: 3) == 3)
        #expect(SpeechTransportBudget.resourceTimeout(request: 60) == 60)
    }
}
