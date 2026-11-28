import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the directory trim in `NewChatRequest.isValid`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
/// The instruction trim in `NewChatRequest.cleanedInstruction` still uses `CharacterSet.whitespacesAndNewlines`.
@Suite("New chat directory box")
struct NewChatDirectoryBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(NewChatDirectoryBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(NewChatDirectoryBox.blankScalars.count == 5)
        #expect(NewChatDirectoryBox.blankScalars.contains(" "))
        #expect(NewChatDirectoryBox.blankScalars.contains("\t"))
        #expect(NewChatDirectoryBox.blankScalars.contains("\n"))
        #expect(NewChatDirectoryBox.blankScalars.contains("\r"))
        #expect(NewChatDirectoryBox.blankScalars.contains("\u{00A0}"))
        #expect(!NewChatDirectoryBox.blankScalars.contains("\u{200B}"))
        #expect(!NewChatDirectoryBox.blankScalars.contains("\u{000B}"))
        #expect(!NewChatDirectoryBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedDirectory() {
        #expect(NewChatDirectoryBox.trimmedDirectory("\u{200B}") == "\u{200B}")
        #expect(NewChatDirectoryBox.trimmedDirectory(" \u{200B} ") == "\u{200B}")
        #expect(NewChatDirectoryBox.trimmedDirectory("\t\u{200B}\n") == "\u{200B}")
        #expect(NewChatDirectoryBox.trimmedDirectory("\u{200B}proj") == "\u{200B}proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("proj\u{200B}") == "proj\u{200B}")
        #expect(NewChatDirectoryBox.trimmedDirectory(" \t\n\r\u{00A0}") == "")
        #expect(NewChatDirectoryBox.trimmedDirectory("") == "")
        #expect(NewChatDirectoryBox.trimmedDirectory("\u{000B}proj") == "\u{000B}proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("\u{3000}proj") == "\u{3000}proj")
        #expect(NewChatDirectoryBox.trimmedDirectory(" \tproj\r\n") == "proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("\u{00A0}proj\u{00A0}") == "proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("proj") == "proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("a\u{200B}b") == "a\u{200B}b")
        #expect(NewChatDirectoryBox.trimmedDirectory("\nproj") == "proj")
        #expect(NewChatDirectoryBox.trimmedDirectory("\rproj") == "proj")
    }

    @Test func aZeroWidthSpaceStaysOnANewChatDirectory() {
        let kept = NewChatRequest(tool: .claude, directory: "\u{200B}", instruction: "look")
        #expect(kept.isValid)
        #expect(kept.command == .agent(tool: .claude, project: nil, dir: "\u{200B}", task: "look"))
        let wrapped = NewChatRequest(tool: .claude, directory: " \u{200B} ", instruction: "look")
        #expect(NewChatDirectoryBox.trimmedDirectory(wrapped.directory) == "\u{200B}")
        #expect(wrapped.isValid)
        #expect(wrapped.command == .agent(tool: .claude, project: nil, dir: " \u{200B} ", task: "look"))
        #expect(NewChatRequest(tool: .claude, directory: "\u{200B}proj", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "proj\u{200B}", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\u{3000}", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\u{3000}proj", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\u{000B}dir", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\u{000B}", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\n", instruction: "look").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: "\r", instruction: "look").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: "\nproj", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: "\rproj", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: " \t\n\r\u{00A0}", instruction: "look").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: "\u{00A0}proj\u{00A0}", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .claude, directory: " \tproj\r\n", instruction: "look").isValid)
        #expect(NewChatRequest(tool: .codex, directory: "/Users/t/dev/zeus", instruction: "  fix the failing tests ").isValid)
        #expect(NewChatRequest(tool: .codex, directory: "/Users/t/dev/zeus", instruction: "  fix the failing tests ").cleanedInstruction == "fix the failing tests")
        #expect(NewChatRequest(tool: .claude, directory: "/r", instruction: "  ").isValid == false)
        #expect(NewChatRequest(tool: .claude, directory: " ", instruction: "look").isValid == false)
        let job = NewChatRequest(tool: .claude, directory: "\u{200B}", instruction: "look").job()
        #expect(job.directory == "\u{200B}")
        #expect(job.commandLine == "'claude' 'look'")
        #expect(CodingTool.claude.arguments(task: "\u{200B}look") == ["look"])
    }
}
