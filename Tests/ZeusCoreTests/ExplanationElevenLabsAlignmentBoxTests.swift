import Foundation
import Testing
@testable import ZeusCore

/// The break answer for ElevenLabs alignment tokens. A zero-width space stays in the word.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("Explanation ElevenLabs alignment box")
struct ExplanationElevenLabsAlignmentBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.count == 25)
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{0009}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{000A}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{000B}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{000C}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{000D}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{0020}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{0085}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{00A0}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{1680}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2000}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2001}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2002}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2003}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2004}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2005}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2006}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2007}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2008}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2009}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{200A}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2028}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{2029}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{202F}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{205F}"))
        #expect(ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{3000}"))
        #expect(!ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{200B}"))
        #expect(!ExplanationElevenLabsAlignmentBox.blankScalars.contains("\u{200C}"))
    }

    @Test func aZeroWidthSpaceIsNotABreak() {
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{200B}") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{200C}") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("H") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("Hi") == false)
    }

    @Test func aZeroWidthSpaceBesideABlankIsNotABreak() {
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(" \u{200B}") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{200B} ") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\n\u{200B}\t") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{00A0}\u{200B}") == false)
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{3000}\u{200B}\u{2028}") == false)
    }

    @Test func anEmptyTokenIsABreakAndNamedBlanksAreBreaks() {
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(""))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(" "))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\n"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\t"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\r"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{000B}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{000C}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{0085}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{00A0}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{1680}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{2000}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{200A}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{2028}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{2029}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{202F}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{205F}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{3000}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(" \t\n\u{00A0}\u{3000}"))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak("\u{200B}") == false)
    }

    @Test func aTokenOfOnlyNamedBlanksIsABreak() {
        let blanks = ExplanationElevenLabsAlignmentBox.blankScalars.map { String($0) }
        #expect(blanks.count == 25)
        for token in blanks {
            #expect(ExplanationElevenLabsAlignmentBox.isBreak(token))
        }
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(blanks.joined()))
        #expect(ExplanationElevenLabsAlignmentBox.isBreak(blanks.joined() + "\u{200B}") == false)
    }
}
