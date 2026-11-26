import Foundation
import Testing
@testable import ZeusCore

@Suite("Partial action gate box")
struct PartialActionGateBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PartialActionGateBox.blankScalars.contains(" "))
        #expect(PartialActionGateBox.blankScalars.contains("\t"))
        #expect(PartialActionGateBox.blankScalars.contains("\n"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{000B}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{000C}"))
        #expect(PartialActionGateBox.blankScalars.contains("\r"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{0085}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{00A0}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{1680}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{2000}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{200A}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{2028}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{2029}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{202F}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{205F}"))
        #expect(PartialActionGateBox.blankScalars.contains("\u{3000}"))
        #expect(!PartialActionGateBox.blankScalars.contains("\u{200B}"))
        #expect(PartialActionGateBox.trimmedKey("\u{200B}") == "\u{200B}")
        #expect(PartialActionGateBox.trimmedKey(" \u{200B} ") == "\u{200B}")
        #expect(PartialActionGateBox.trimmedKey(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aKeyOfOnlyNamedBlanksIsEmpty() {
        #expect(PartialActionGateBox.trimmedKey("") == "")
        #expect(PartialActionGateBox.trimmedKey(" \t\n\r") == "")
        #expect(PartialActionGateBox.trimmedKey("\u{00A0}") == "")
        #expect(PartialActionGateBox.trimmedKey("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(PartialActionGateBox.trimmedKey("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheKey() {
        #expect(PartialActionGateBox.trimmedKey("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(PartialActionGateBox.trimmedKey("\u{200B}open") == "\u{200B}open")
        #expect(PartialActionGateBox.trimmedKey("open\u{200B}") == "open\u{200B}")
        #expect(PartialActionGateBox.trimmedKey(" \nopen\t") == "open")
    }

    @Test func aZeroWidthSpaceKeepsItsOwnActionKey() {
        #expect(PartialActionGate.key("\u{200B}") == "\u{200B}")
        #expect(PartialActionGate.key("\u{200B}Open") == "\u{200b}open")
        #expect(PartialActionGate.key("  OPEN \n") == "open")
        #expect(PartialActionGate.key(" \u{00A0}\u{200B}\u{3000} ") == "\u{200B}")
        var gate = PartialActionGate()
        gate.observePartial("\u{200B}open")
        let plain = gate.mayActOnPartial("open")
        let marked = gate.mayActOnPartial("\u{200B}open")
        #expect(!plain)
        #expect(marked)
    }
}
