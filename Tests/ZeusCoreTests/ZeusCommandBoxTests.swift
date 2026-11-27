import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a Zeus command. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Zeus command box")
struct ZeusCommandBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ZeusCommandBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ZeusCommandBox.blankScalars.count == 5)
        #expect(ZeusCommandBox.blankScalars.contains(" "))
        #expect(ZeusCommandBox.blankScalars.contains("\t"))
        #expect(ZeusCommandBox.blankScalars.contains("\n"))
        #expect(ZeusCommandBox.blankScalars.contains("\r"))
        #expect(ZeusCommandBox.blankScalars.contains("\u{00A0}"))
        #expect(!ZeusCommandBox.blankScalars.contains("\u{200B}"))
        #expect(!ZeusCommandBox.blankScalars.contains("\u{000B}"))
        #expect(!ZeusCommandBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInCommandText() {
        #expect(ZeusCommandBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(ZeusCommandBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(ZeusCommandBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(ZeusCommandBox.trimmedText("\u{200B}open repo") == "\u{200B}open repo")
        #expect(ZeusCommandBox.trimmedText("open repo\u{200B}") == "open repo\u{200B}")
        #expect(ZeusCommandBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(ZeusCommandBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(ZeusCommandBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(ZeusCommandBox.trimmedText(" \thello\r\n") == "hello")
        #expect(ZeusCommandBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ZeusCommandBox.trimmedText("\u{200B}./a.wav") == "\u{200B}./a.wav")
    }

    @Test func aZeroWidthSpaceDoesNotActAsAnEmptyCommand() throws {
        let kept = try ZeusCLI.parse(["say", "\u{200B}"], id: "zw")
        #expect(kept.command?.op == .say)
        #expect(kept.command?.text == "\u{200B}")
        let asked = try ZeusCLI.parse(["ask", "\u{200B}open", "repo"], id: "ask")
        #expect(asked.command?.text == "\u{200B}open repo")
        let vertical = try ZeusCLI.parse(["say", "\u{000B}hello"], id: "vt")
        #expect(vertical.command?.text == "\u{000B}hello")
        let ideographic = try ZeusCLI.parse(["say", "\u{3000}hello"], id: "ideo")
        #expect(ideographic.command?.text == "\u{3000}hello")
        let trimmed = try ZeusCLI.parse(["say", " \t\u{00A0}hello\n\r"], id: "trim")
        #expect(trimmed.command?.text == "hello")
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["say", " \t\n\r\u{00A0}"]) }
        #expect(throws: ZeusCLIError.self) { try ZeusCLI.parse(["status", "\u{200B}"]) }
        let status = try ZeusCLI.parse(["status", " \t\u{00A0}"], id: "st")
        #expect(status.command?.op == .status)
        #expect(status.command?.text == nil)
        #expect(ZeusCLI.normalizeDebugText("dictate-file ./a.wav").hasSuffix("/a.wav"))
        #expect(ZeusCLI.normalizeDebugText("wake-file relative.wav").contains("relative.wav"))
        #expect(ZeusCLI.normalizeDebugText("dictate-file \t./a.wav\n").hasSuffix("/a.wav"))
        #expect(ZeusCLI.normalizeDebugText("dictate-file ./a.wav\u{00A0}").hasSuffix("/a.wav"))
        #expect(ZeusCLI.normalizeDebugText("dictate-file \t\n\r\u{00A0}") == "dictate-file ")
        #expect(ZeusCLI.normalizeDebugText("not-a-file ./a.wav") == "not-a-file ./a.wav")
    }
}
