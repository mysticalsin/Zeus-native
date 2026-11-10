import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Prompt budget")
struct PromptBudgetTests {
    @Test func theSystemPromptStaysUnderTheLimit() {
        for personality in [ZeusPersonality.ultron, .plain] {
            let prompt = ZeusPrompt.system(personality: personality)
            #expect(ModelBudget.promptFits(prompt), "\(personality) is \(prompt.count) characters")
        }
    }
}
