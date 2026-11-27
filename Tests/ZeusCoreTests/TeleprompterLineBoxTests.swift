import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a teleprompter line. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Teleprompter line box")
struct TeleprompterLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TeleprompterLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TeleprompterLineBox.blankScalars.count == 5)
        #expect(TeleprompterLineBox.blankScalars.contains(" "))
        #expect(TeleprompterLineBox.blankScalars.contains("\t"))
        #expect(TeleprompterLineBox.blankScalars.contains("\n"))
        #expect(TeleprompterLineBox.blankScalars.contains("\r"))
        #expect(TeleprompterLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!TeleprompterLineBox.blankScalars.contains("\u{200B}"))
        #expect(!TeleprompterLineBox.blankScalars.contains("\u{000B}"))
        #expect(!TeleprompterLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedLine() {
        #expect(TeleprompterLineBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(TeleprompterLineBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(TeleprompterLineBox.trimmedLine("\t\u{200B}\n") == "\u{200B}")
        #expect(TeleprompterLineBox.trimmedLine("\u{200B}Hi") == "\u{200B}Hi")
        #expect(TeleprompterLineBox.trimmedLine("Hi\u{200B}") == "Hi\u{200B}")
        #expect(TeleprompterLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        #expect(TeleprompterLineBox.trimmedLine("") == "")
        #expect(TeleprompterLineBox.trimmedLine("\u{000B}Hi") == "\u{000B}Hi")
        #expect(TeleprompterLineBox.trimmedLine("\u{3000}Hi") == "\u{3000}Hi")
        #expect(TeleprompterLineBox.trimmedLine(" \tHi\r\n") == "Hi")
        #expect(TeleprompterLineBox.trimmedLine("\u{00A0}Hi\u{00A0}") == "Hi")
        #expect(TeleprompterLineBox.trimmedLine("Hi\u{00A0}there") == "Hi\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInTheScript() {
        let zwsp = "\u{200B}"
        #expect(TeleprompterBox.blocks(in: zwsp).map(\.text) == [zwsp])
        #expect(TeleprompterBox.blocks(in: zwsp).map(\.isCue) == [false])
        #expect(TeleprompterBox.blocks(in: "#\(zwsp)").map(\.text) == [zwsp])
        #expect(TeleprompterBox.blocks(in: "#\(zwsp)").map(\.isCue) == [true])
        #expect(TeleprompterBox.blocks(in: " \(zwsp) ").map(\.text) == [zwsp])
        #expect(TeleprompterBox.blocks(in: "#\(zwsp)Intro").map(\.text) == ["\(zwsp)Intro"])
        #expect(TeleprompterBox.blocks(in: "Intro\(zwsp)").map(\.text) == ["Intro\(zwsp)"])
        #expect(TeleprompterBox.blocks(in: " \t\n\r\u{00A0}").isEmpty)
        #expect(TeleprompterBox.blocks(in: "#   ").isEmpty)
        #expect(TeleprompterBox.blocks(in: "#").isEmpty)
        #expect(TeleprompterBox.blocks(in: "#\u{3000}Demo").map(\.text) == ["\u{3000}Demo"])
        #expect(TeleprompterBox.blocks(in: " \tHi\r\n").map(\.text) == ["Hi"])
        #expect(TeleprompterBox.blocks(in: "\u{00A0}# Intro\u{00A0}").map(\.text) == ["Intro"])
        #expect(TeleprompterBox.blocks(in: "#\u{00A0}Intro\u{00A0}").map(\.text) == ["Intro"])
        #expect(TeleprompterBox.blocks(in: "Hi\u{00A0}there").map(\.text) == ["Hi\u{00A0}there"])
    }
}
