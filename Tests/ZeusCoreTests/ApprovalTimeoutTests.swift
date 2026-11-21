import Foundation
import Testing
@testable import ZeusCore

@Suite("Approval timeout")
struct ApprovalTimeoutTests {
    @Test func highRiskDeniesWhenNobodyAnswers() {
        #expect(HookDecision.timeoutVerdict(for: .high) == .deny)
        #expect(HookDecision.timeoutVerdict(for: .medium) == .ask)
        #expect(HookDecision.timeoutVerdict(for: .low) == .ask)
    }
}
