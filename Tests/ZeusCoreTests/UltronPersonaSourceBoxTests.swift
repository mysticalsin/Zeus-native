import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in the persona prompt block. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Ultron persona source box")
struct UltronPersonaSourceBoxTests {
    private let fallback = "COMPILED FALLBACK"

    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(UltronPersonaSourceBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(UltronPersonaSourceBox.blankScalars.count == 5)
        #expect(UltronPersonaSourceBox.blankScalars.contains(" "))
        #expect(UltronPersonaSourceBox.blankScalars.contains("\t"))
        #expect(UltronPersonaSourceBox.blankScalars.contains("\n"))
        #expect(UltronPersonaSourceBox.blankScalars.contains("\r"))
        #expect(UltronPersonaSourceBox.blankScalars.contains("\u{00A0}"))
        #expect(!UltronPersonaSourceBox.blankScalars.contains("\u{200B}"))
        #expect(!UltronPersonaSourceBox.blankScalars.contains("\u{000B}"))
        #expect(!UltronPersonaSourceBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATrimmedBlock() {
        #expect(UltronPersonaSourceBox.trimmedBlock("\u{200B}") == "\u{200B}")
        #expect(UltronPersonaSourceBox.trimmedBlock(" \u{200B} ") == "\u{200B}")
        #expect(UltronPersonaSourceBox.trimmedBlock("\t\u{200B}\n") == "\u{200B}")
        #expect(UltronPersonaSourceBox.trimmedBlock("\u{200B}The block") == "\u{200B}The block")
        #expect(UltronPersonaSourceBox.trimmedBlock("The block\u{200B}") == "The block\u{200B}")
        #expect(UltronPersonaSourceBox.trimmedBlock(" \t\n\r\u{00A0}") == "")
        #expect(UltronPersonaSourceBox.trimmedBlock("\u{000B}Tony") == "\u{000B}Tony")
        #expect(UltronPersonaSourceBox.trimmedBlock("\u{3000}Tony") == "\u{3000}Tony")
        #expect(UltronPersonaSourceBox.trimmedBlock(" \tThe block\r\n") == "The block")
        #expect(UltronPersonaSourceBox.trimmedBlock("\u{00A0}The block\u{00A0}") == "The block")
        #expect(UltronPersonaSourceBox.trimmedBlock("a\u{00A0}b") == "a\u{00A0}b")
        #expect(UltronPersonaSourceBox.trimmedBlock("The block.\nSecond line.") == "The block.\nSecond line.")
    }

    @Test func aZeroWidthSpaceIsThePromptBlockInsteadOfTheFallback() {
        let begin = UltronPersonaSource.beginMarker
        let end = UltronPersonaSource.endMarker
        func block(_ inner: String) -> String {
            UltronPersonaSource.promptBlock(markdown: "\(begin)\(inner)\(end)", fallback: fallback)
        }
        #expect(block("\u{200B}") == "\u{200B}")
        #expect(block(" \u{200B} ") == "\u{200B}")
        #expect(block("\u{200B}The block") == "\u{200B}The block")
        #expect(block("\u{000B}") == "\u{000B}")
        #expect(block("\u{3000}kept") == "\u{3000}kept")
        #expect(block(" \t\n\r\u{00A0}") == fallback)
        #expect(block("\n  \n") == fallback)
        #expect(UltronPersonaSource.promptBlock(markdown: nil, fallback: fallback) == fallback)
        #expect(UltronPersonaSource.promptBlock(markdown: "no markers", fallback: fallback) == fallback)
        let markdown = "# Title\nintro\n\(begin)\n  The block.\nSecond line.\n\(end)\nafter"
        #expect(UltronPersonaSource.promptBlock(markdown: markdown, fallback: fallback) == "The block.\nSecond line.")
        #expect(block("\u{00A0}The block.\nSecond line.\u{00A0}") == "The block.\nSecond line.")
    }
}
