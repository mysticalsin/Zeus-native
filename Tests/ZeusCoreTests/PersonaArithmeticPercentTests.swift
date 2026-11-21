import Testing
@testable import ZeusCore

@Suite("Local percent answers")
struct PersonaArithmeticPercentTests {
    @Test func eighteenPercentOf240DoesNotNeedAModel() {
        #expect(PersonaArithmetic.answer(for: "18% of 240") == "43.2.")
        #expect(PersonaArithmetic.answer(for: "18 percent of 240") == "43.2.")
        #expect(PersonaArithmetic.answer(for: "what's 50% of 80") == "40.")
    }

    @Test func existingWholeNumberArithmeticStaysLocal() {
        #expect(PersonaArithmetic.answer(for: "what is 17 times 23") == "391.")
        #expect(PersonaArithmetic.answer(for: "what is 10 plus 2") == "12.")
        #expect(PersonaArithmetic.answer(for: "what is the capital of Australia") == nil)
    }
}
