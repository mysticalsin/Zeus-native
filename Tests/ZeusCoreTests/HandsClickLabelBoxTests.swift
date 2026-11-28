import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a click label. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Hands click label box")
struct HandsClickLabelBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(HandsClickLabelBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(HandsClickLabelBox.blankScalars.count == 5)
        #expect(HandsClickLabelBox.blankScalars.contains(" "))
        #expect(HandsClickLabelBox.blankScalars.contains("\t"))
        #expect(HandsClickLabelBox.blankScalars.contains("\n"))
        #expect(HandsClickLabelBox.blankScalars.contains("\r"))
        #expect(HandsClickLabelBox.blankScalars.contains("\u{00A0}"))
        #expect(!HandsClickLabelBox.blankScalars.contains("\u{200B}"))
        #expect(!HandsClickLabelBox.blankScalars.contains("\u{000B}"))
        #expect(!HandsClickLabelBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedLabel() {
        #expect(HandsClickLabelBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(HandsClickLabelBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(HandsClickLabelBox.trimmedLabel("\t\u{200B}\n") == "\u{200B}")
        #expect(HandsClickLabelBox.trimmedLabel("\u{200B}send") == "\u{200B}send")
        #expect(HandsClickLabelBox.trimmedLabel("send\u{200B}") == "send\u{200B}")
        #expect(HandsClickLabelBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(HandsClickLabelBox.trimmedLabel("") == "")
        #expect(HandsClickLabelBox.trimmedLabel("\u{000B}send") == "\u{000B}send")
        #expect(HandsClickLabelBox.trimmedLabel("\u{3000}send") == "\u{3000}send")
        #expect(HandsClickLabelBox.trimmedLabel(" \tsend\r\n") == "send")
        #expect(HandsClickLabelBox.trimmedLabel("\u{00A0}send\u{00A0}") == "send")
        #expect(HandsClickLabelBox.trimmedLabel("send") == "send")
    }

    @Test func aZeroWidthSpaceStaysOnAClickLabel() {
        #expect(HandsGate.intent(clicking: "\u{200B}send") == nil)
        #expect(HandsGate.intent(clicking: "send\u{200B}") == nil)
        #expect(HandsGate.intent(clicking: " \u{200B} ") == nil)
        #expect(HandsGate.intent(clicking: "\u{3000}send") == nil)
        #expect(HandsGate.intent(clicking: "\u{000B}delete") == nil)
        #expect(HandsGate.intent(clicking: " send ") == .send(to: "the open draft", text: "Send"))
        #expect(HandsGate.intent(clicking: "\tSend\n") == .send(to: "the open draft", text: "Send"))
        #expect(HandsGate.intent(clicking: "\u{00A0}send\u{00A0}") == .send(to: "the open draft", text: "Send"))
        #expect(HandsGate.intent(clicking: " Delete ") == .delete(files: [" Delete "]))
        #expect(HandsGate.intent(clicking: "\u{00A0}Buy\u{00A0}") == .buy(item: "\u{00A0}Buy\u{00A0}", price: "the shown price"))
        #expect(HandsGate.intent(clicking: "purchase") == .buy(item: "purchase", price: "the shown price"))
        #expect(HandsGate.intent(clicking: " \t\n\r\u{00A0}") == nil)
        #expect(HandsGate.intent(clicking: "hello") == nil)
        #expect(HandsGate.intent(clicking: "") == nil)
    }
}
