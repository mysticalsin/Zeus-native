import Testing
@testable import ZeusCore

@Suite("Act first, no filler preamble")
struct ActFirstFillerTests {
    @Test func aPointerQuestionSuppressesThePreamble() {
        #expect(ActFirst.suppressesFiller("Where do I click to change my wallpaper?"))
        #expect(ActFirst.suppressesFiller("What is this window?"))
        #expect(ActFirst.suppressesFiller("Draw how my router talks to my Mac"))
    }

    @Test func aPlainQuestionStillAllowsOnePreamble() {
        #expect(!ActFirst.suppressesFiller("What's the capital of Australia and its population?"))
        #expect(!ActFirst.suppressesFiller("18% of 240"))
        #expect(!ActFirst.suppressesFiller("Make it shorter"))
    }

    @Test func aToolOrPointerClosesTheFillerGate() {
        var gate = TurnFillerGate()
        gate.noteToolOrPointer()
        let spoken = gate.take()
        #expect(!spoken)
    }

    @Test func onePreambleStillFitsATurnThatHasNotActed() {
        var gate = TurnFillerGate()
        let first = gate.take()
        let second = gate.take()
        #expect(first)
        #expect(!second)
    }
}
