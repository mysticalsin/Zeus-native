import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a terminal task. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Terminal launch box")
struct TerminalLaunchBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TerminalLaunchBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TerminalLaunchBox.blankScalars.count == 5)
        #expect(TerminalLaunchBox.blankScalars.contains(" "))
        #expect(TerminalLaunchBox.blankScalars.contains("\t"))
        #expect(TerminalLaunchBox.blankScalars.contains("\n"))
        #expect(TerminalLaunchBox.blankScalars.contains("\r"))
        #expect(TerminalLaunchBox.blankScalars.contains("\u{00A0}"))
        #expect(!TerminalLaunchBox.blankScalars.contains("\u{200B}"))
        #expect(!TerminalLaunchBox.blankScalars.contains("\u{000B}"))
        #expect(!TerminalLaunchBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATask() {
        #expect(TerminalLaunchBox.trimmedTask("\u{200B}") == "\u{200B}")
        #expect(TerminalLaunchBox.trimmedTask(" \u{200B} ") == "\u{200B}")
        #expect(TerminalLaunchBox.trimmedTask("\t\u{200B}\n") == "\u{200B}")
        #expect(TerminalLaunchBox.trimmedTask("\u{200B}-flag") == "\u{200B}-flag")
        #expect(TerminalLaunchBox.trimmedTask("fix tests\u{200B}") == "fix tests\u{200B}")
        #expect(TerminalLaunchBox.trimmedTask(" \t\n\r\u{00A0}") == "")
        #expect(TerminalLaunchBox.trimmedTask("\u{000B}hello") == "\u{000B}hello")
        #expect(TerminalLaunchBox.trimmedTask("\u{3000}hello") == "\u{3000}hello")
        #expect(TerminalLaunchBox.trimmedTask(" \thello\r\n") == "hello")
        #expect(TerminalLaunchBox.trimmedTask("\u{00A0}hello\u{00A0}") == "hello")
        #expect(TerminalLaunchBox.trimmedTask(" \t\u{00A0}-flag\n\r") == "-flag")
    }

    @Test func aZeroWidthSpaceDoesNotActAsAnEmptyTask() {
        #expect(CodingTool.claude.arguments(task: "\u{200B}") == ["\u{200B}"])
        #expect(CodingTool.claude.arguments(task: " \u{200B} ") == ["\u{200B}"])
        #expect(CodingTool.gemini.arguments(task: "\u{200B}") == ["-i", "\u{200B}"])
        #expect(CodingTool.claude.arguments(task: "\u{200B}-flag") == ["\u{200B}-flag"])
        #expect(CodingTool.gemini.arguments(task: "\u{200B}-flag") == ["-i", "\u{200B}-flag"])
        #expect(CodingTool.claude.arguments(task: " \t\u{00A0}-flag\n\r") == ["Task: -flag"])
        #expect(CodingTool.gemini.arguments(task: " \t\u{00A0}-x\n") == ["-i", "Task: -x"])
        #expect(CodingTool.claude.arguments(task: " \t\n\r\u{00A0}").isEmpty)
        #expect(CodingTool.codex.arguments(task: "\u{00A0}").isEmpty)
        #expect(CodingTool.claude.arguments(task: "\u{000B}hello") == ["\u{000B}hello"])
        #expect(CodingTool.claude.arguments(task: "\u{3000}hello") == ["\u{3000}hello"])
        #expect(CodingTool.claude.arguments(task: " \thello\r\n") == ["hello"])
        #expect(CodingTool.cursorAgent.arguments(task: "\u{00A0}fix tests\u{00A0}") == ["fix tests"])
        #expect(CodingTool.claude.arguments(task: "   ").isEmpty)
        #expect(CodingTool.claude.arguments(task: "--version") == ["Task: --version"])
    }
}
