import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a private action secret. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Private action receipt box")
struct PrivateActionReceiptBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PrivateActionReceiptBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PrivateActionReceiptBox.blankScalars.count == 5)
        #expect(PrivateActionReceiptBox.blankScalars.contains(" "))
        #expect(PrivateActionReceiptBox.blankScalars.contains("\t"))
        #expect(PrivateActionReceiptBox.blankScalars.contains("\n"))
        #expect(PrivateActionReceiptBox.blankScalars.contains("\r"))
        #expect(PrivateActionReceiptBox.blankScalars.contains("\u{00A0}"))
        #expect(!PrivateActionReceiptBox.blankScalars.contains("\u{200B}"))
        #expect(!PrivateActionReceiptBox.blankScalars.contains("\u{000B}"))
        #expect(!PrivateActionReceiptBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInASecret() {
        #expect(PrivateActionReceiptBox.trimmedSecret("\u{200B}") == "\u{200B}")
        #expect(PrivateActionReceiptBox.trimmedSecret(" \u{200B} ") == "\u{200B}")
        #expect(PrivateActionReceiptBox.trimmedSecret("\t\u{200B}\n") == "\u{200B}")
        #expect(PrivateActionReceiptBox.trimmedSecret("\u{200B}clipboard contents here") == "\u{200B}clipboard contents here")
        #expect(PrivateActionReceiptBox.trimmedSecret("clipboard contents here\u{200B}") == "clipboard contents here\u{200B}")
        #expect(PrivateActionReceiptBox.trimmedSecret(" \t\n\r\u{00A0}") == "")
        #expect(PrivateActionReceiptBox.trimmedSecret("\u{000B}clipboard contents here") == "\u{000B}clipboard contents here")
        #expect(PrivateActionReceiptBox.trimmedSecret("\u{3000}clipboard contents here") == "\u{3000}clipboard contents here")
        #expect(PrivateActionReceiptBox.trimmedSecret(" \tclipboard contents here\r\n") == "clipboard contents here")
        #expect(PrivateActionReceiptBox.trimmedSecret("\u{00A0}clipboard contents here\u{00A0}") == "clipboard contents here")
    }

    @Test func aZeroWidthSpaceStillRecordsAndDoesNotPublishAsThePlainWords() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let receipt = PrivateActionReceipt(id: id, kind: .clipboard, undoLabel: "clipboard contents here")
        #expect(receipt.publishes(" \tclipboard contents here\r\n"))
        #expect(receipt.publishes("\u{00A0}clipboard contents here\u{00A0}"))
        #expect(!receipt.publishes(" \t\n\r\u{00A0}"))
        #expect(!receipt.publishes("\u{200B}clipboard contents here"))
        #expect(!receipt.publishes("\u{200B}"))
        #expect(!receipt.publishes("\u{000B}clipboard contents here"))
        #expect(!receipt.publishes("\u{3000}clipboard contents here"))

        var blanks = PrivateActionLedger()
        #expect(blanks.record(kind: .note, withheld: [" \t\n\r\u{00A0}"], restore: "earlier", token: "t") == nil)
        #expect(blanks.current == nil)

        var kept = PrivateActionLedger()
        let recorded = kept.record(kind: .note, withheld: ["\u{200B}"], restore: "earlier", token: "t")
        #expect(recorded != nil)
        #expect(recorded?.notchLine == "Note saved")
        #expect(recorded?.publishes("\u{200B}") == false)
        #expect(kept.undo()?.restore == "earlier")

        var vertical = PrivateActionLedger()
        #expect(vertical.record(kind: .note, withheld: ["\u{000B}"], restore: "earlier", token: "v") != nil)
        var ideographic = PrivateActionLedger()
        #expect(ideographic.record(kind: .file, withheld: ["\u{3000}"], restore: "earlier", token: "i") != nil)
    }
}
