import Foundation
import Testing
@testable import ZeusCore

@Suite("Private notch action receipts")
struct PrivateActionReceiptTests {
    private let noteBody = "SECRET-NOTE-buy-the-blue-notebook-9f3a"
    private let filePath = "/Users/example/SECRET-FILE-taxes-2026.pdf"
    private let clip = "SECRET-CLIP-account-number-4410"
    private let spoken = "SECRET-DICTATION-call-marina-at-four"

    private func ledger(kind: PrivateActionKind, withheld: [String], restore: String, token: String,
                         share: Bool = false) -> (PrivateActionLedger, PrivateActionReceipt) {
        var ledger = PrivateActionLedger()
        let receipt = ledger.record(kind: kind, withheld: withheld, restore: restore, token: token, share: share)!
        return (ledger, receipt)
    }

    @Test func eachZeusActionIsPrivateAndShowsOnlyItsTitle() {
        let cases: [(PrivateActionKind, [String], String)] = [
            (.note, [noteBody], "Note saved"),
            (.file, [filePath, "SECRET-FILE-taxes-2026.pdf"], "File placed"),
            (.clipboard, [clip], "Copied"),
            (.dictation, [spoken], "Dictated"),
        ]
        for (kind, withheld, title) in cases {
            let (_, receipt) = ledger(kind: kind, withheld: withheld, restore: "previous", token: "token")
            #expect(receipt.isPrivate)
            #expect(receipt.visibility == .private)
            #expect(receipt.notchLine == title)
            #expect(receipt.sharedBody == nil)
            #expect(receipt.undoLabel == "Undo")
            for secret in withheld {
                #expect(!receipt.publishes(secret))
                #expect(!receipt.notchLine.localizedCaseInsensitiveContains(secret))
            }
        }
    }

    @Test func aShortClipboardWordStillRecordsWithoutShowingIt() {
        var ledger = PrivateActionLedger()
        let receipt = ledger.record(kind: .clipboard, withheld: ["a"], restore: "", token: "id")
        #expect(receipt?.notchLine == "Copied")
        #expect(receipt?.isPrivate == true)
        #expect(receipt?.publishes("a") == false)
    }

    @Test func anEmptyActionDoesNotLeaveAReceipt() {
        var ledger = PrivateActionLedger()
        #expect(ledger.record(kind: .note, withheld: ["  ", ""], restore: "", token: "note") == nil)
        #expect(ledger.current == nil)
        #expect(ledger.undo() == nil)
    }

    @Test func sharingIsOptInAndStillHidesTheContents() {
        let (ledger, receipt) = ledger(kind: .clipboard, withheld: [clip], restore: "old", token: "id", share: true)
        #expect(!receipt.isPrivate)
        #expect(receipt.sharedBody == "Copied")
        #expect(!receipt.publishes(clip))
        #expect(ledger.current?.sharedBody == "Copied")
    }

    @Test func undoReturnsTheHiddenRestoreOnceAndDropsTheReceipt() {
        var ledger = PrivateActionLedger()
        let id = UUID()
        _ = ledger.record(kind: .note, withheld: [noteBody], restore: "earlier note", token: "note", id: id)
        let outcome = ledger.undo()
        #expect(outcome?.restore == "earlier note")
        #expect(outcome?.effect.receiptID == id)
        #expect(outcome?.effect.kind == .note)
        #expect(outcome?.effect.token == "note")
        #expect(ledger.current == nil)
        #expect(ledger.undo() == nil)
        #expect(!(outcome?.effect.token.contains(noteBody) ?? true))
    }

    @Test func aNewerActionReplacesTheOneUndoWouldHaveReversed() {
        var ledger = PrivateActionLedger()
        _ = ledger.record(kind: .clipboard, withheld: [clip], restore: "first", token: "one")
        _ = ledger.record(kind: .dictation, withheld: [spoken], restore: "", token: "two")
        let outcome = ledger.undo()
        #expect(outcome?.effect.kind == .dictation)
        #expect(outcome?.effect.token == "two")
        #expect(outcome?.restore == "")
        #expect(ledger.undo() == nil)
    }

    @Test func dismissDropsUndoBeforeTheHoldEnds() {
        var ledger = PrivateActionLedger()
        _ = ledger.record(kind: .file, withheld: [filePath], restore: "", token: "abc")
        ledger.dismiss()
        #expect(ledger.current == nil)
        #expect(ledger.undo() == nil)
        #expect(PrivateActionLedger.hold == 8)
    }

    @Test func bareUUndoesOnlyTheClosedNotchReceipt() {
        let claim = PrivateActionLedger.claimsUndo
        #expect(claim(characters: "u", command: false, shift: false, option: false, control: false,
                       decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(claim(characters: "U", command: false, shift: false, option: false, control: false,
                       decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: true, shift: false, option: false, control: false,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: true, option: false, control: false,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: false, option: true, control: false,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: false, option: false, control: true,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: false, option: false, control: false,
                        decisionRowVisible: true, receiptVisible: true, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: false, option: false, control: false,
                        decisionRowVisible: false, receiptVisible: false, panelOpen: false))
        #expect(!claim(characters: "u", command: false, shift: false, option: false, control: false,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: true))
        #expect(!claim(characters: "z", command: false, shift: false, option: false, control: false,
                        decisionRowVisible: false, receiptVisible: true, panelOpen: false))
    }

    @Test func receiptNamesStayOnTheNotchControls() {
        #expect(PrivateActionReceiptID.row == "notch.actionReceipt")
        #expect(PrivateActionReceiptID.undo == "notch.actionReceipt.undo")
    }
}
