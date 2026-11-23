import Testing
@testable import ZeusCore

@Suite("Approval sync")
struct ApprovalSyncTests {
    @Test func answeringTheTerminalClearsTheCardWithinTheBudget() {
        var pair = ApprovalPair.bothPending
        let latency = pair.answer(on: .terminal, now: 10)
        #expect(latency <= ApprovalPair.clearBudget)
        #expect(pair.terminalPending == false)
        #expect(pair.cardPending == false)
        #expect(pair.answeredOn == .terminal)
        #expect(pair.cardCount == 0)
    }

    @Test func answeringTheCardClearsTheTerminalWithinTheBudget() {
        var pair = ApprovalPair.bothPending
        let latency = pair.answer(on: .card, now: 10)
        #expect(latency <= ApprovalPair.clearBudget)
        #expect(pair.terminalPending == false)
        #expect(pair.cardPending == false)
        #expect(pair.answeredOn == .card)
        #expect(pair.cardCount == 0)
    }

    @Test func aSecondAnswerDoesNotLeaveACardBehind() {
        var pair = ApprovalPair.bothPending
        _ = pair.answer(on: .terminal, now: 10)
        let again = pair.answer(on: .card, now: 10.2)
        #expect(again <= ApprovalPair.clearBudget)
        #expect(pair.cardCount == 0)
        #expect(pair.terminalPending == false)
        #expect(pair.answeredOn == .terminal)
    }
}
