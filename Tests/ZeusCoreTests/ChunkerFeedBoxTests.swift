import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the sentence trim inside `SentenceChunker.feed`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Chunker feed box")
struct ChunkerFeedBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ChunkerFeedBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ChunkerFeedBox.blankScalars.count == 5)
        #expect(ChunkerFeedBox.blankScalars.contains(" "))
        #expect(ChunkerFeedBox.blankScalars.contains("\t"))
        #expect(ChunkerFeedBox.blankScalars.contains("\n"))
        #expect(ChunkerFeedBox.blankScalars.contains("\r"))
        #expect(ChunkerFeedBox.blankScalars.contains("\u{00A0}"))
        #expect(!ChunkerFeedBox.blankScalars.contains("\u{200B}"))
        #expect(!ChunkerFeedBox.blankScalars.contains("\u{000B}"))
        #expect(!ChunkerFeedBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedFeed() {
        #expect(ChunkerFeedBox.trimmedFeed("\u{200B}") == "\u{200B}")
        #expect(ChunkerFeedBox.trimmedFeed(" \u{200B} ") == "\u{200B}")
        #expect(ChunkerFeedBox.trimmedFeed("\t\u{200B}\n") == "\u{200B}")
        #expect(ChunkerFeedBox.trimmedFeed("\u{200B}Hi") == "\u{200B}Hi")
        #expect(ChunkerFeedBox.trimmedFeed("Hi\u{200B}") == "Hi\u{200B}")
        #expect(ChunkerFeedBox.trimmedFeed(" \t\n\r\u{00A0}") == "")
        #expect(ChunkerFeedBox.trimmedFeed("") == "")
        #expect(ChunkerFeedBox.trimmedFeed("\u{000B}Hi") == "\u{000B}Hi")
        #expect(ChunkerFeedBox.trimmedFeed("\u{3000}Hi") == "\u{3000}Hi")
        #expect(ChunkerFeedBox.trimmedFeed(" \tHi\r\n") == "Hi")
        #expect(ChunkerFeedBox.trimmedFeed("\u{00A0}Hi\u{00A0}") == "Hi")
        #expect(ChunkerFeedBox.trimmedFeed("Hi") == "Hi")
        #expect(ChunkerFeedBox.trimmedFeed("H\u{200B}i") == "H\u{200B}i")
        #expect(ChunkerFeedBox.trimmedFeed("\n") == "")
        #expect(ChunkerFeedBox.trimmedFeed("\r") == "")
        #expect(ChunkerFeedBox.trimmedFeed("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheChunkerSentence() {
        #expect(sentences("\u{200B}Hi. ") == ["\u{200B}Hi."])
        #expect(sentences("\u{200B}Hi. ") != ["Hi."])
        #expect(sentences(" \u{200B}Hi. ") == ["\u{200B}Hi."])
        #expect(sentences("\t\u{200B}Hi.\n") == ["\u{200B}Hi."])
        #expect(sentences("Hi\u{200B}. ") == ["Hi\u{200B}."])
        #expect(sentences("Hi\u{200B}. ") != ["Hi."])
        #expect(sentences("H\u{200B}i. ") == ["H\u{200B}i."])
        #expect(sentences("H\u{200B}i. ") != ["Hi."])
        #expect(sentences("\n\u{200B}. ") == ["\u{200B}."])
        #expect(sentences("\n\u{200B}. ") != [])
        #expect(sentences("   Hi. ") == ["Hi."])
        #expect(sentences(" \t\n\r\u{00A0}Hi. ") == ["Hi."])
        #expect(sentences("\u{00A0}Hi. ") == ["Hi."])
        #expect(sentences(" \tHi.\r\n") == ["Hi."])
        #expect(sentences("\u{3000}Hi. ") == ["\u{3000}Hi."])
        #expect(sentences("\u{3000}Hi. ") != ["Hi."])
        #expect(sentences("\u{000B}Hi. ") == ["\u{000B}Hi."])
        #expect(sentences("\u{000B}Hi. ") != ["Hi."])
        #expect(sentences("Hi. ") == ["Hi."])
        #expect(sentences("\n. ") == [])
        #expect(sentences("\r. ") == [])
        #expect(sentences("Hi. \u{200B}Yo. ") == ["Hi.", "\u{200B}Yo."])
        #expect(sentences("Hi. \u{200B}Yo. ") != ["Hi.", "Yo."])
        #expect(sentences("It is 3.5 percent. Dr. Lee agrees. Done. ") == ["It is 3.5 percent.", "Dr. Lee agrees.", "Done."])
    }

    private func sentences(_ text: String) -> [String] {
        var chunker = SentenceChunker()
        return chunker.feed(text)
    }
}
