import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a hub approval command. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Hub approval command box")
struct HubApprovalCommandBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(HubApprovalCommandBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(HubApprovalCommandBox.blankScalars.count == 5)
        #expect(HubApprovalCommandBox.blankScalars.contains(" "))
        #expect(HubApprovalCommandBox.blankScalars.contains("\t"))
        #expect(HubApprovalCommandBox.blankScalars.contains("\n"))
        #expect(HubApprovalCommandBox.blankScalars.contains("\r"))
        #expect(HubApprovalCommandBox.blankScalars.contains("\u{00A0}"))
        #expect(!HubApprovalCommandBox.blankScalars.contains("\u{200B}"))
        #expect(!HubApprovalCommandBox.blankScalars.contains("\u{000B}"))
        #expect(!HubApprovalCommandBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedCommand() {
        #expect(HubApprovalCommandBox.trimmedCommand("\u{200B}") == "\u{200B}")
        #expect(HubApprovalCommandBox.trimmedCommand(" \u{200B} ") == "\u{200B}")
        #expect(HubApprovalCommandBox.trimmedCommand("\t\u{200B}\n") == "\u{200B}")
        #expect(HubApprovalCommandBox.trimmedCommand("\u{200B}rm notes.txt") == "\u{200B}rm notes.txt")
        #expect(HubApprovalCommandBox.trimmedCommand("rm notes.txt\u{200B}") == "rm notes.txt\u{200B}")
        #expect(HubApprovalCommandBox.trimmedCommand(" \t\n\r\u{00A0}") == "")
        #expect(HubApprovalCommandBox.trimmedCommand("") == "")
        #expect(HubApprovalCommandBox.trimmedCommand("\u{000B}rm") == "\u{000B}rm")
        #expect(HubApprovalCommandBox.trimmedCommand("\u{3000}rm") == "\u{3000}rm")
        #expect(HubApprovalCommandBox.trimmedCommand(" \trm notes.txt\r\n") == "rm notes.txt")
        #expect(HubApprovalCommandBox.trimmedCommand("\u{00A0}rm notes.txt\u{00A0}") == "rm notes.txt")
        #expect(HubApprovalCommandBox.trimmedCommand("rm\u{00A0}notes.txt") == "rm\u{00A0}notes.txt")
    }

    @Test func aZeroWidthSpaceStaysOnTheApprovalCommand() {
        let stuck = HubApprovalImpact.preview(tool: "Bash", command: "\u{200B}rm notes.txt", input: nil)
        #expect(stuck.deletes.isEmpty)
        #expect(stuck.isEmpty)

        let blanks = HubApprovalImpact.preview(tool: "Bash", command: " \t\n\r\u{00A0}", input: nil)
        #expect(blanks.isEmpty)

        let vertical = HubApprovalImpact.preview(tool: "Bash", command: "\u{000B}rm notes.txt", input: nil)
        #expect(vertical.deletes.isEmpty)
        #expect(vertical.isEmpty)

        let ideographic = HubApprovalImpact.preview(tool: "Bash", command: "\u{3000}rm notes.txt", input: nil)
        #expect(ideographic.deletes.isEmpty)
        #expect(ideographic.isEmpty)

        let named = HubApprovalImpact.preview(tool: "Bash", command: " \trm notes.txt\r\n", input: nil)
        #expect(named.deletes == ["notes.txt"])

        let noBreak = HubApprovalImpact.preview(tool: "Bash", command: "\u{00A0}rm notes.txt\u{00A0}", input: nil)
        #expect(noBreak.deletes == ["notes.txt"])

        let input = JSONValue.object(["command": .string("\u{200B}rm notes.txt")])
        let fromInput = HubApprovalImpact.preview(tool: "Bash", command: "rm notes.txt", input: input)
        #expect(fromInput.deletes.isEmpty)
        #expect(fromInput.isEmpty)

        let plain = HubApprovalImpact.preview(tool: "Bash", command: "rm notes.txt", input: nil)
        #expect(plain.deletes == ["notes.txt"])
    }
}
