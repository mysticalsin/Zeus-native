import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the instruction trim in `NewChatRequest.cleanedInstruction`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
/// The directory trim in `NewChatRequest.isValid` still uses `CharacterSet.whitespaces`.
@Suite("New chat instruction box")
struct NewChatInstructionBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(NewChatInstructionBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(NewChatInstructionBox.blankScalars.count == 5)
        #expect(NewChatInstructionBox.blankScalars.contains(" "))
        #expect(NewChatInstructionBox.blankScalars.contains("\t"))
        #expect(NewChatInstructionBox.blankScalars.contains("\n"))
        #expect(NewChatInstructionBox.blankScalars.contains("\r"))
        #expect(NewChatInstructionBox.blankScalars.contains("\u{00A0}"))
        #expect(!NewChatInstructionBox.blankScalars.contains("\u{200B}"))
        #expect(!NewChatInstructionBox.blankScalars.contains("\u{000B}"))
        #expect(!NewChatInstructionBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedInstruction() {
        #expect(NewChatInstructionBox.trimmedInstruction("\u{200B}") == "\u{200B}")
        #expect(NewChatInstructionBox.trimmedInstruction(" \u{200B} ") == "\u{200B}")
        #expect(NewChatInstructionBox.trimmedInstruction("\t\u{200B}\n") == "\u{200B}")
        #expect(NewChatInstructionBox.trimmedInstruction("\u{200B}look") == "\u{200B}look")
        #expect(NewChatInstructionBox.trimmedInstruction("look\u{200B}") == "look\u{200B}")
        #expect(NewChatInstructionBox.trimmedInstruction(" \t\n\r\u{00A0}") == "")
        #expect(NewChatInstructionBox.trimmedInstruction("") == "")
        #expect(NewChatInstructionBox.trimmedInstruction("\u{000B}look") == "\u{000B}look")
        #expect(NewChatInstructionBox.trimmedInstruction("\u{3000}look") == "\u{3000}look")
        #expect(NewChatInstructionBox.trimmedInstruction(" \tlook\r\n") == "look")
        #expect(NewChatInstructionBox.trimmedInstruction("\u{00A0}look\u{00A0}") == "look")
        #expect(NewChatInstructionBox.trimmedInstruction("look") == "look")
        #expect(NewChatInstructionBox.trimmedInstruction("a\u{200B}b") == "a\u{200B}b")
        #expect(NewChatInstructionBox.trimmedInstruction("\nlook") == "look")
        #expect(NewChatInstructionBox.trimmedInstruction("\rlook") == "look")
    }

    @Test func aZeroWidthSpaceStaysOnACleanedInstruction() {
        let kept = NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{200B}look")
        #expect(kept.cleanedInstruction == "\u{200B}look")
        #expect(kept.isValid)
        #expect(kept.command == .agent(tool: .claude, project: nil, dir: "proj", task: "\u{200B}look"))
        let wrapped = NewChatRequest(tool: .claude, directory: "proj", instruction: " \u{200B} ")
        #expect(wrapped.cleanedInstruction == "\u{200B}")
        #expect(wrapped.isValid)
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{200B}").cleanedInstruction == "\u{200B}")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{3000}look").cleanedInstruction == "\u{3000}look")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{000B}look").cleanedInstruction == "\u{000B}look")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\nlook").cleanedInstruction == "look")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\rlook").cleanedInstruction == "look")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{00A0}look\u{00A0}").cleanedInstruction == "look")
        #expect(NewChatRequest(tool: .claude, directory: "proj", instruction: " \tlook\r\n").cleanedInstruction == "look")
        #expect(NewChatRequest(tool: .codex, directory: "/Users/t/dev/zeus", instruction: "  fix the failing tests ").isValid)
        #expect(NewChatRequest(tool: .codex, directory: "/Users/t/dev/zeus", instruction: "  fix the failing tests ").cleanedInstruction == "fix the failing tests")
        #expect(NewChatRequest(tool: .claude, directory: "/r", instruction: "  ").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: " ", instruction: "look").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: "\u{200B}", instruction: "look").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: "\u{000B}dir", instruction: "look").isValid)
        let job = NewChatRequest(tool: .claude, directory: "proj", instruction: "\u{200B}look").job()
        #expect(job.commandLine == "'claude' 'look'")
    }
}
