import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a joined chunk. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Chunk transcript joiner box")
struct ChunkTranscriptJoinerBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ChunkTranscriptJoinerBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ChunkTranscriptJoinerBox.blankScalars.count == 5)
        #expect(ChunkTranscriptJoinerBox.blankScalars.contains(" "))
        #expect(ChunkTranscriptJoinerBox.blankScalars.contains("\t"))
        #expect(ChunkTranscriptJoinerBox.blankScalars.contains("\n"))
        #expect(ChunkTranscriptJoinerBox.blankScalars.contains("\r"))
        #expect(ChunkTranscriptJoinerBox.blankScalars.contains("\u{00A0}"))
        #expect(!ChunkTranscriptJoinerBox.blankScalars.contains("\u{200B}"))
        #expect(!ChunkTranscriptJoinerBox.blankScalars.contains("\u{000B}"))
        #expect(!ChunkTranscriptJoinerBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInAPart() {
        #expect(ChunkTranscriptJoinerBox.trimmedPart("\u{200B}") == "\u{200B}")
        #expect(ChunkTranscriptJoinerBox.trimmedPart(" \u{200B} ") == "\u{200B}")
        #expect(ChunkTranscriptJoinerBox.trimmedPart("\t\u{200B}\n") == "\u{200B}")
        #expect(ChunkTranscriptJoinerBox.trimmedPart("\u{200B}Hello") == "\u{200B}Hello")
        #expect(ChunkTranscriptJoinerBox.trimmedPart("Hello\u{200B}") == "Hello\u{200B}")
        #expect(ChunkTranscriptJoinerBox.trimmedPart(" \t\n\r\u{00A0}") == "")
        #expect(ChunkTranscriptJoinerBox.trimmedPart("\u{000B}Hi") == "\u{000B}Hi")
        #expect(ChunkTranscriptJoinerBox.trimmedPart("\u{3000}Hi") == "\u{3000}Hi")
    }

    @Test func aZeroWidthSpaceStaysInTheJoinedTranscript() {
        #expect(ChunkTranscriptJoiner.join(["\u{200B}"]) == "\u{200B}")
        #expect(ChunkTranscriptJoiner.join([" \u{200B} "]) == "\u{200B}")
        #expect(ChunkTranscriptJoiner.join(["\u{200B}Hello", " there\u{200B}"]) == "\u{200B}Hello there\u{200B}")
        #expect(ChunkTranscriptJoiner.join([" \t", "\n", "\r", "\u{00A0}"]) == "")
        #expect(ChunkTranscriptJoiner.join(["\u{00A0}Hi\u{00A0}"]) == "Hi")
        #expect(ChunkTranscriptJoiner.join(["Hello there.", " ", "  How are you? "]) == "Hello there. How are you?")
        #expect(ChunkTranscriptJoiner.join([]) == "")
    }
}
