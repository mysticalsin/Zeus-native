import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the clause trim inside `SentenceSplitter.takeEarlyClause`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Early clause box")
struct EarlyClauseBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(EarlyClauseBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(EarlyClauseBox.blankScalars.count == 5)
        #expect(EarlyClauseBox.blankScalars.contains(" "))
        #expect(EarlyClauseBox.blankScalars.contains("\t"))
        #expect(EarlyClauseBox.blankScalars.contains("\n"))
        #expect(EarlyClauseBox.blankScalars.contains("\r"))
        #expect(EarlyClauseBox.blankScalars.contains("\u{00A0}"))
        #expect(!EarlyClauseBox.blankScalars.contains("\u{200B}"))
        #expect(!EarlyClauseBox.blankScalars.contains("\u{000B}"))
        #expect(!EarlyClauseBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedClause() {
        #expect(EarlyClauseBox.trimmedClause("\u{200B}") == "\u{200B}")
        #expect(EarlyClauseBox.trimmedClause(" \u{200B} ") == "\u{200B}")
        #expect(EarlyClauseBox.trimmedClause("\t\u{200B}\n") == "\u{200B}")
        #expect(EarlyClauseBox.trimmedClause("\u{200B}Good") == "\u{200B}Good")
        #expect(EarlyClauseBox.trimmedClause("Good\u{200B}") == "Good\u{200B}")
        #expect(EarlyClauseBox.trimmedClause(" \t\n\r\u{00A0}") == "")
        #expect(EarlyClauseBox.trimmedClause("") == "")
        #expect(EarlyClauseBox.trimmedClause("\u{000B}Good") == "\u{000B}Good")
        #expect(EarlyClauseBox.trimmedClause("\u{3000}Good") == "\u{3000}Good")
        #expect(EarlyClauseBox.trimmedClause(" \tGood\r\n") == "Good")
        #expect(EarlyClauseBox.trimmedClause("\u{00A0}Good\u{00A0}") == "Good")
        #expect(EarlyClauseBox.trimmedClause("Good") == "Good")
        #expect(EarlyClauseBox.trimmedClause("Go\u{200B}od") == "Go\u{200B}od")
        #expect(EarlyClauseBox.trimmedClause("\n") == "")
        #expect(EarlyClauseBox.trimmedClause("\r") == "")
        #expect(EarlyClauseBox.trimmedClause("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheEarlyClause() {
        var lead = SentenceSplitter()
        #expect(lead.feed("\u{200B}Good evening Tony, the rest stays") == ["\u{200B}Good evening Tony,"])
        var trail = SentenceSplitter()
        #expect(trail.feed("Good evening Tony\u{200B}, the rest stays") == ["Good evening Tony\u{200B},"])
        var only = SentenceSplitter()
        #expect(only.feed("\u{200B}\u{200B}Good evening Tony, the rest stays") == ["\u{200B}\u{200B}Good evening Tony,"])
        var second = SentenceSplitter()
        #expect(second.feed("Good evening \u{200B}Tony, the rest stays") == ["Good evening \u{200B}Tony,"])
        var middle = SentenceSplitter()
        #expect(middle.feed("Good eve\u{200B}ning Tony, the rest stays") == ["Good eve\u{200B}ning Tony,"])
        var plain = SentenceSplitter()
        #expect(plain.feed("Good evening Tony, the rest stays") == ["Good evening Tony,"])
        var semicolon = SentenceSplitter()
        #expect(semicolon.feed("Good evening Tony; the rest stays") == ["Good evening Tony,"])
        var ideographic = SentenceSplitter()
        #expect(ideographic.feed("\u{3000}Good evening Tony, the rest stays") == ["\u{3000}Good evening Tony,"])
        var vertical = SentenceSplitter()
        #expect(vertical.feed("\u{000B}Good evening Tony, the rest stays") == ["\u{000B}Good evening Tony,"])
        var noBreak = SentenceSplitter()
        #expect(noBreak.feed("\u{00A0}Good evening Tony\u{00A0}, the rest stays") == ["Good evening Tony,"])
        var edges = SentenceSplitter()
        #expect(edges.feed(" \tGood evening Tony\r, the rest stays") == ["Good evening Tony,"])
        var short = SentenceSplitter()
        #expect(short.feed("Hi there, the rest stays") == [])
        var bare = SentenceSplitter()
        #expect(bare.feed("") == [])
        var blanks = SentenceSplitter()
        #expect(blanks.feed(" \t\r\u{00A0}, one two three") == [])
        var noComma = SentenceSplitter()
        #expect(noComma.feed("Good evening Tony and friends") == [])
        var once = SentenceSplitter()
        #expect(once.feed("Good evening Tony, and then later, more words stay") == ["Good evening Tony,"])
    }
}
