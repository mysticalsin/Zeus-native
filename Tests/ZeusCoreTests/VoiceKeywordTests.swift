import Testing
@testable import ZeusCore

@Suite struct VoiceKeywordTests {
    @Test func ownApproveWordsReplaceTheDefaults() {
        #expect(ApprovalPhrases.verdict(for: "ship it", approve: ["ship it"], deny: [], open: []) == .allow)
        #expect(ApprovalPhrases.verdict(for: "yes", approve: ["ship it"], deny: [], open: []) == nil)
    }

    @Test func negativesAlwaysWin() {
        #expect(ApprovalPhrases.verdict(for: "no ship it", approve: ["ship it"], deny: [], open: []) == .deny)
        #expect(ApprovalPhrases.verdict(for: "hold on", approve: ["ok"], deny: ["hold on"], open: []) == .deny)
    }

    @Test func openHandsBackToTheApp() {
        #expect(ApprovalPhrases.verdict(for: "open it", approve: ["ok"], deny: [], open: ["open"]) == .ask)
    }

    @Test func emptyListsFallBackToBuiltIns() {
        #expect(ApprovalPhrases.verdict(for: "go ahead", approve: [], deny: [], open: []) == .allow)
        #expect(ApprovalPhrases.verdict(for: "please do this long thing now for me", approve: [], deny: [], open: []) == nil)
    }
}
