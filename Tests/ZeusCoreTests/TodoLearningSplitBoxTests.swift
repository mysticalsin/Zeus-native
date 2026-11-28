import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the part trim inside `TodoLearning.suggestSplit`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("To-do learning split box")
struct TodoLearningSplitBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TodoLearningSplitBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TodoLearningSplitBox.blankScalars.count == 5)
        #expect(TodoLearningSplitBox.blankScalars.contains(" "))
        #expect(TodoLearningSplitBox.blankScalars.contains("\t"))
        #expect(TodoLearningSplitBox.blankScalars.contains("\n"))
        #expect(TodoLearningSplitBox.blankScalars.contains("\r"))
        #expect(TodoLearningSplitBox.blankScalars.contains("\u{00A0}"))
        #expect(!TodoLearningSplitBox.blankScalars.contains("\u{200B}"))
        #expect(!TodoLearningSplitBox.blankScalars.contains("\u{000B}"))
        #expect(!TodoLearningSplitBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPart() {
        #expect(TodoLearningSplitBox.trimmedPart("\u{200B}") == "\u{200B}")
        #expect(TodoLearningSplitBox.trimmedPart(" \u{200B} ") == "\u{200B}")
        #expect(TodoLearningSplitBox.trimmedPart("\t\u{200B}\n") == "\u{200B}")
        #expect(TodoLearningSplitBox.trimmedPart("\u{200B}call") == "\u{200B}call")
        #expect(TodoLearningSplitBox.trimmedPart("call\u{200B}") == "call\u{200B}")
        #expect(TodoLearningSplitBox.trimmedPart(" \t\n\r\u{00A0}") == "")
        #expect(TodoLearningSplitBox.trimmedPart("") == "")
        #expect(TodoLearningSplitBox.trimmedPart("\u{000B}call") == "\u{000B}call")
        #expect(TodoLearningSplitBox.trimmedPart("\u{3000}call") == "\u{3000}call")
        #expect(TodoLearningSplitBox.trimmedPart(" \tcall\r\n") == "call")
        #expect(TodoLearningSplitBox.trimmedPart("\u{00A0}call\u{00A0}") == "call")
        #expect(TodoLearningSplitBox.trimmedPart("call") == "call")
        #expect(TodoLearningSplitBox.trimmedPart("ca\u{200B}ll") == "ca\u{200B}ll")
        #expect(TodoLearningSplitBox.trimmedPart("\n") == "")
        #expect(TodoLearningSplitBox.trimmedPart("\r") == "")
        #expect(TodoLearningSplitBox.trimmedPart("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheSplitParts() {
        let learning = TodoLearning()
        let lead = "\u{200B}call Anna tomorrow and send the invoice"
        #expect(learning.suggestSplit(lead)?.split == ["\u{200B}call Anna tomorrow", "send the invoice"])
        let trail = "call Anna tomorrow and send the invoice\u{200B}"
        #expect(learning.suggestSplit(trail)?.split == ["call Anna tomorrow", "send the invoice\u{200B}"])
        let only = "call Anna tomorrow please and \u{200B}\u{200B}"
        #expect(learning.suggestSplit(only)?.split == ["call Anna tomorrow please", "\u{200B}\u{200B}"])
        let second = "call Anna tomorrow and \u{200B}send the invoice"
        #expect(learning.suggestSplit(second)?.split == ["call Anna tomorrow", "\u{200B}send the invoice"])
        let middle = "call An\u{200B}na tomorrow and send the invoice"
        #expect(learning.suggestSplit(middle)?.split == ["call An\u{200B}na tomorrow", "send the invoice"])
        let plain = "call Anna tomorrow and send the invoice"
        #expect(learning.suggestSplit(plain)?.split == ["call Anna tomorrow", "send the invoice"])
        #expect(learning.suggestSplit(plain)?.kind == "split")
        #expect(learning.suggestSplit(plain)?.title == plain)
        #expect(learning.suggestSplit(plain)?.due == nil)
        #expect(learning.suggestSplit(plain)?.reason == "Looks like 2 tasks. Split them?")
        let known = "call Ana tomorrow and send the invoice Friday and book the dentist"
        #expect(learning.suggestSplit(known)?.split == [
            "call Ana tomorrow", "send the invoice Friday", "book the dentist",
        ])
        #expect(learning.suggestSplit(known)?.reason == "Looks like 3 tasks. Split them?")
        var off = TodoLearning()
        off.enabled = false
        #expect(off.suggestSplit(plain) == nil)
        #expect(learning.suggestSplit("call and mail") == nil)
        #expect(learning.suggestSplit("") == nil)
        #expect(learning.suggestSplit(" \t\n\r\u{00A0}") == nil)
        #expect(learning.suggestSplit(String(repeating: " ", count: 28)) == nil)
        #expect(learning.suggestSplit(lead)?.title == lead)
    }
}
