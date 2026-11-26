import Foundation
import Testing
@testable import ZeusCore

/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("Spoken approval capture box")
struct SpokenApprovalCaptureBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(SpokenApprovalCaptureBox.blankScalars.contains(" "))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\t"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\n"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{000B}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{000C}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\r"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{0085}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{00A0}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{1680}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{2000}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{200A}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{2028}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{2029}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{202F}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{205F}"))
        #expect(SpokenApprovalCaptureBox.blankScalars.contains("\u{3000}"))
        #expect(!SpokenApprovalCaptureBox.blankScalars.contains("\u{200B}"))
        #expect(SpokenApprovalCaptureBox.trimmedCardID("\u{200B}") == "\u{200B}")
        #expect(SpokenApprovalCaptureBox.trimmedCardID(" \u{200B} ") == "\u{200B}")
        #expect(SpokenApprovalCaptureBox.trimmedCardID(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aCardOfOnlyNamedBlanksIsMissing() {
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "") == nil)
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: " \t\n\r") == nil)
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "\u{00A0}") == nil)
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == nil)
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheCardId() {
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "\u{200B}card") == "\u{200B}card")
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: "card\u{200B}") == "card\u{200B}")
        #expect(SpokenApprovalCapture.atSpeechStart(displayedCardID: " \ncard-a\t") == "card-a")
    }

    @Test func aYesAppliesToTheZeroWidthCardThatWasUp() {
        let captured = SpokenApprovalCapture.atSpeechStart(displayedCardID: " \u{200B} ")
        #expect(captured == "\u{200B}")
        #expect(SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: "\u{200B}"))
        #expect(!SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: "card-b"))
        #expect(!SpokenApprovalCapture.applies(capturedCardID: captured, displayedCardID: nil))
    }
}
