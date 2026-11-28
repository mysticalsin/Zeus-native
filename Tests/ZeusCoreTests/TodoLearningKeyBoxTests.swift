import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a to-do title key. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("To-do learning key box")
struct TodoLearningKeyBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TodoLearningKeyBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TodoLearningKeyBox.blankScalars.count == 5)
        #expect(TodoLearningKeyBox.blankScalars.contains(" "))
        #expect(TodoLearningKeyBox.blankScalars.contains("\t"))
        #expect(TodoLearningKeyBox.blankScalars.contains("\n"))
        #expect(TodoLearningKeyBox.blankScalars.contains("\r"))
        #expect(TodoLearningKeyBox.blankScalars.contains("\u{00A0}"))
        #expect(!TodoLearningKeyBox.blankScalars.contains("\u{200B}"))
        #expect(!TodoLearningKeyBox.blankScalars.contains("\u{000B}"))
        #expect(!TodoLearningKeyBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedKey() {
        #expect(TodoLearningKeyBox.trimmedKey("\u{200B}") == "\u{200B}")
        #expect(TodoLearningKeyBox.trimmedKey(" \u{200B} ") == "\u{200B}")
        #expect(TodoLearningKeyBox.trimmedKey("\t\u{200B}\n") == "\u{200B}")
        #expect(TodoLearningKeyBox.trimmedKey("\u{200B}buy milk") == "\u{200B}buy milk")
        #expect(TodoLearningKeyBox.trimmedKey("buy milk\u{200B}") == "buy milk\u{200B}")
        #expect(TodoLearningKeyBox.trimmedKey(" \t\n\r\u{00A0}") == "")
        #expect(TodoLearningKeyBox.trimmedKey("") == "")
        #expect(TodoLearningKeyBox.trimmedKey("\u{000B}buy") == "\u{000B}buy")
        #expect(TodoLearningKeyBox.trimmedKey("\u{3000}buy") == "\u{3000}buy")
        #expect(TodoLearningKeyBox.trimmedKey(" \tbuy milk\r\n") == "buy milk")
        #expect(TodoLearningKeyBox.trimmedKey("\u{00A0}buy milk\u{00A0}") == "buy milk")
        #expect(TodoLearningKeyBox.trimmedKey("buy milk") == "buy milk")
    }

    @Test func aZeroWidthSpaceStaysOnTheLearningKey() {
        #expect(TodoLearningKeyBox.trimmedKey(" \u{200B}buy milk") == "\u{200B}buy milk")
        #expect(TodoLearningKeyBox.trimmedKey(" buy milk ") == "buy milk")
        #expect(TodoLearningKeyBox.trimmedKey(" \t\n\r\u{00A0}") == "")
        #expect(TodoLearning.key(for: "\u{200B}") == "\u{200B}")
        #expect(TodoLearning.key(for: " \u{200B} ") == "\u{200B}")
        #expect(TodoLearning.key(for: "\u{200B}Buy Milk") == "\u{200B}buy milk")
        #expect(TodoLearning.key(for: "Buy Milk\u{200B}") == "buy milk\u{200B}")
        #expect(TodoLearning.key(for: "  Buy Milk  ") == "buy milk")
        #expect(TodoLearning.key(for: "\u{00A0}Buy Milk\u{00A0}") == "buy milk")
        #expect(TodoLearning.key(for: " \t\n\r\u{00A0}") == "")
        #expect(TodoLearning.key(for: "") == "")
        #expect(TodoLearning.key(for: "\u{3000}Buy") == "\u{3000}buy")
        #expect(TodoLearning.key(for: "\u{000B}Buy") == "\u{000B}buy")
        #expect(TodoLearning.key(for: "Buy Milk") == "buy milk")
    }
}
