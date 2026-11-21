import Testing
@testable import ZeusCore

@Suite("Answer card clears on the next question")
struct AnswerCardClearanceTests {
    @Test func aNewQuestionClearsAVisibleCard() {
        var cards = AnswerCardClearance()
        let first = cards.questionStarted()
        let shown = cards.show(generation: first)
        #expect(shown)
        #expect(cards.visible)
        let second = cards.questionStarted()
        #expect(second != first)
        #expect(!cards.visible)
    }

    @Test func aLateShowFromThePreviousQuestionCannotBringTheCardBack() {
        var cards = AnswerCardClearance()
        let first = cards.questionStarted()
        let shown = cards.show(generation: first)
        #expect(shown)
        let second = cards.questionStarted()
        let stale = cards.show(generation: first)
        #expect(stale == false)
        #expect(cards.visible == false)
        let current = cards.show(generation: second)
        #expect(current)
        #expect(cards.visible)
    }
}
