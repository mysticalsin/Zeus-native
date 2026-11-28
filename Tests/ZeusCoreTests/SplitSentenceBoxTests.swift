import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a sentence cut from streamed speech. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Split sentence box")
struct SplitSentenceBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(SplitSentenceBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(SplitSentenceBox.blankScalars.count == 5)
        #expect(SplitSentenceBox.blankScalars.contains(" "))
        #expect(SplitSentenceBox.blankScalars.contains("\t"))
        #expect(SplitSentenceBox.blankScalars.contains("\n"))
        #expect(SplitSentenceBox.blankScalars.contains("\r"))
        #expect(SplitSentenceBox.blankScalars.contains("\u{00A0}"))
        #expect(!SplitSentenceBox.blankScalars.contains("\u{200B}"))
        #expect(!SplitSentenceBox.blankScalars.contains("\u{000B}"))
        #expect(!SplitSentenceBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedSentence() {
        #expect(SplitSentenceBox.trimmedSentence("\u{200B}") == "\u{200B}")
        #expect(SplitSentenceBox.trimmedSentence(" \u{200B} ") == "\u{200B}")
        #expect(SplitSentenceBox.trimmedSentence("\t\u{200B}\n") == "\u{200B}")
        #expect(SplitSentenceBox.trimmedSentence("\u{200B}Hi.") == "\u{200B}Hi.")
        #expect(SplitSentenceBox.trimmedSentence("Hi.\u{200B}") == "Hi.\u{200B}")
        #expect(SplitSentenceBox.trimmedSentence(" \t\n\r\u{00A0}") == "")
        #expect(SplitSentenceBox.trimmedSentence("") == "")
        #expect(SplitSentenceBox.trimmedSentence("\u{000B}Hi.") == "\u{000B}Hi.")
        #expect(SplitSentenceBox.trimmedSentence("\u{3000}Hi.") == "\u{3000}Hi.")
        #expect(SplitSentenceBox.trimmedSentence(" \tHi.\r\n") == "Hi.")
        #expect(SplitSentenceBox.trimmedSentence("\u{00A0}Hi.\u{00A0}") == "Hi.")
        #expect(SplitSentenceBox.trimmedSentence("Hello.") == "Hello.")
    }

    @Test func aZeroWidthSpaceStaysOnTheSplitSentence() {
        #expect(SplitSentenceBox.trimmedSentence(" \u{200B}Hi.") == "\u{200B}Hi.")
        #expect(SplitSentenceBox.trimmedSentence(" Hello. ") == "Hello.")
        #expect(SplitSentenceBox.trimmedSentence(" \t\n\r\u{00A0}") == "")
        var splitter = SentenceSplitter()
        #expect(splitter.feed("\u{200B}Hi. ") == ["\u{200B}Hi."])
        splitter = SentenceSplitter()
        #expect(splitter.feed(" Hi. ") == ["Hi."])
        splitter = SentenceSplitter()
        #expect(splitter.feed(" \t\n\r\u{00A0}. ") == [])
        splitter = SentenceSplitter()
        #expect(splitter.feed("\u{3000}Hi. ") == ["\u{3000}Hi."])
        splitter = SentenceSplitter()
        #expect(splitter.feed("\u{000B}Hi. ") == ["\u{000B}Hi."])
        splitter = SentenceSplitter()
        #expect(splitter.feed("\u{00A0}Hi. ") == ["Hi."])
        splitter = SentenceSplitter()
        #expect(splitter.feed("\nHello. ") == ["Hello."])
        splitter = SentenceSplitter()
        #expect(splitter.feed("Hello\n") == ["Hello"])
        splitter = SentenceSplitter()
        #expect(splitter.feed("Good evening, Tony. ") == ["Good evening, Tony."])
    }
}
