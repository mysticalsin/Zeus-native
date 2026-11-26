import Foundation
import Testing
@testable import ZeusCore

/// The blank answer for a spoken question. A zero-width space stays inside the word.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("Question sort box")
struct QuestionSortBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(QuestionSortBox.blankScalars.count == 25)
        #expect(QuestionSortBox.blankScalars.contains("\u{0009}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{000A}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{000B}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{000C}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{000D}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{0020}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{0085}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{00A0}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{1680}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2000}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2001}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2002}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2003}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2004}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2005}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2006}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2007}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2008}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2009}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{200A}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2028}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{2029}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{202F}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{205F}"))
        #expect(QuestionSortBox.blankScalars.contains("\u{3000}"))
        #expect(!QuestionSortBox.blankScalars.contains("\u{200B}"))
        #expect(!QuestionSortBox.blankScalars.contains("\u{200C}"))
    }

    @Test func aZeroWidthSpaceIsNotABlank() {
        #expect(QuestionSortBox.isBlank("\u{200B}") == false)
        #expect(QuestionSortBox.isBlank("\u{200C}") == false)
        #expect(QuestionSortBox.isBlank("H") == false)
        #expect(QuestionSortBox.isBlank("Hi") == false)
        let glued = QuestionSort.sort("where\u{200B}is the button", knowledgeThrough: 2025)
        #expect(glued.guides == false)
        #expect(glued.webSearch == false)
        let spaced = QuestionSort.sort("where is the button", knowledgeThrough: 2025)
        #expect(spaced.guides)
        #expect(spaced.webSearch == false)
    }

    @Test func aZeroWidthSpaceBesideABlankIsNotABlank() {
        #expect(QuestionSortBox.isBlank(" \u{200B}") == false)
        #expect(QuestionSortBox.isBlank("\u{200B} ") == false)
        #expect(QuestionSortBox.isBlank("\n\u{200B}\t") == false)
        #expect(QuestionSortBox.isBlank("\u{00A0}\u{200B}") == false)
        #expect(QuestionSortBox.isBlank("\u{3000}\u{200B}\u{2028}") == false)
        let glued = QuestionSort.sort("walk\u{200B}me through this", knowledgeThrough: 2025)
        #expect(glued.guides == false)
        #expect(glued.webSearch == false)
    }

    @Test func anEmptyTokenIsNotABlankAndNamedBlanksAreBlanks() {
        #expect(QuestionSortBox.isBlank("") == false)
        #expect(QuestionSortBox.isBlank(" "))
        #expect(QuestionSortBox.isBlank("\n"))
        #expect(QuestionSortBox.isBlank("\t"))
        #expect(QuestionSortBox.isBlank("\r"))
        #expect(QuestionSortBox.isBlank("\u{000B}"))
        #expect(QuestionSortBox.isBlank("\u{000C}"))
        #expect(QuestionSortBox.isBlank("\u{0085}"))
        #expect(QuestionSortBox.isBlank("\u{00A0}"))
        #expect(QuestionSortBox.isBlank("\u{1680}"))
        #expect(QuestionSortBox.isBlank("\u{2000}"))
        #expect(QuestionSortBox.isBlank("\u{200A}"))
        #expect(QuestionSortBox.isBlank("\u{2028}"))
        #expect(QuestionSortBox.isBlank("\u{2029}"))
        #expect(QuestionSortBox.isBlank("\u{202F}"))
        #expect(QuestionSortBox.isBlank("\u{205F}"))
        #expect(QuestionSortBox.isBlank("\u{3000}"))
        #expect(QuestionSortBox.isBlank(" \t\n\u{00A0}\u{3000}"))
        #expect(QuestionSortBox.isBlank("\u{200B}") == false)
        let separated = QuestionSort.sort("where\u{00A0}is the button", knowledgeThrough: 2025)
        #expect(separated.guides)
        #expect(separated.webSearch == false)
    }

    @Test func aTokenOfOnlyNamedBlanksIsABlank() {
        let blanks = QuestionSortBox.blankScalars.map { String($0) }
        #expect(blanks.count == 25)
        for token in blanks {
            #expect(QuestionSortBox.isBlank(token))
        }
        #expect(QuestionSortBox.isBlank(blanks.joined()))
        #expect(QuestionSortBox.isBlank(blanks.joined() + "\u{200B}") == false)
    }
}
