import Testing
@testable import ZeusCore

@Suite struct SpokenApprovalCaptureTests {
    @Test func speechStartKeepsTheCardThatWasUp() {
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "card-a") == "card-a")
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: nil) == nil)
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "  ") == nil)
    }

    @Test func aYesAppliesOnlyToTheCapturedCard() {
        let captured = SpokenApprovalCapture.atSpeechStart(displayedCardID: "card-a")
        #expect(SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: "card-a"))
        #expect(!SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: "card-b"))
    }

    @Test func aYesDoesNotApproveACardThatAppearedAfterSpeechStarted() {
        let captured = SpokenApprovalCapture.atSpeechStart(displayedCardID: nil)
        #expect(!SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: "card-b"))
    }
}
