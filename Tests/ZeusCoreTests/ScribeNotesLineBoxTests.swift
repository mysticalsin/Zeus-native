import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the line trim inside `ScribeExtractiveNotesGenerator.generate`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe notes line box")
struct ScribeNotesLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeNotesLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeNotesLineBox.blankScalars.count == 5)
        #expect(ScribeNotesLineBox.blankScalars.contains(" "))
        #expect(ScribeNotesLineBox.blankScalars.contains("\t"))
        #expect(ScribeNotesLineBox.blankScalars.contains("\n"))
        #expect(ScribeNotesLineBox.blankScalars.contains("\r"))
        #expect(ScribeNotesLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeNotesLineBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeNotesLineBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeNotesLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedLine() {
        #expect(ScribeNotesLineBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(ScribeNotesLineBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(ScribeNotesLineBox.trimmedLine("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeNotesLineBox.trimmedLine("\u{200B}hello") == "\u{200B}hello")
        #expect(ScribeNotesLineBox.trimmedLine("hello\u{200B}") == "hello\u{200B}")
        #expect(ScribeNotesLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        #expect(ScribeNotesLineBox.trimmedLine("") == "")
        #expect(ScribeNotesLineBox.trimmedLine("\u{000B}hello") == "\u{000B}hello")
        #expect(ScribeNotesLineBox.trimmedLine("\u{3000}hello") == "\u{3000}hello")
        #expect(ScribeNotesLineBox.trimmedLine(" \thello\r\n") == "hello")
        #expect(ScribeNotesLineBox.trimmedLine("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ScribeNotesLineBox.trimmedLine("hello") == "hello")
        #expect(ScribeNotesLineBox.trimmedLine("hel\u{200B}lo") == "hel\u{200B}lo")
        #expect(ScribeNotesLineBox.trimmedLine("\n") == "")
        #expect(ScribeNotesLineBox.trimmedLine("\r") == "")
        #expect(ScribeNotesLineBox.trimmedLine("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInExtractiveNotes() throws {
        let session = ScribeSessionID()
        let clock = Date(timeIntervalSince1970: 1_000)
        func notes(_ lines: [(String, Bool)]) throws -> ScribeGeneratedNotes {
            var transcript = ScribeTranscript(session: session)
            for (index, line) in lines.enumerated() {
                transcript.upsert(ScribeTranscriptSegment(
                    id: "s\(index)",
                    session: session,
                    speaker: .unknown,
                    start: TimeInterval(index),
                    end: TimeInterval(index) + 1,
                    text: line.0,
                    isFinal: line.1
                ))
            }
            return try ScribeExtractiveNotesGenerator(summaryLineCount: 3, clock: { clock }).generate(from: transcript)
        }

        let zero = try notes([("\u{200B}", true)])
        #expect(zero.summary == "\u{200B}")
        #expect(zero.decisions.isEmpty)
        #expect(zero.actionItems.isEmpty)
        #expect(zero.generatedAt == clock)
        #expect(zero.method == .extractive)

        let padded = try notes([(" \u{200B} ", true)])
        #expect(padded.summary == "\u{200B}")

        let between = try notes([("\n\u{200B}\r", true)])
        #expect(between.summary == "\u{200B}")

        let leading = try notes([("\u{200B}we decided", true)])
        #expect(leading.summary == "\u{200B}we decided")
        #expect(leading.decisions == ["\u{200B}we decided"])

        let trailing = try notes([("we decided\u{200B}", true)])
        #expect(trailing.summary == "we decided\u{200B}")
        #expect(trailing.decisions == ["we decided\u{200B}"])

        let inside = try notes([("we\u{200B}decided", true)])
        #expect(inside.summary == "we\u{200B}decided")
        #expect(inside.decisions == ["we\u{200B}decided"])

        let ideographic = try notes([("\u{3000}", true)])
        #expect(ideographic.summary == "\u{3000}")

        let ideographicLine = try notes([("\u{3000}we decided", true)])
        #expect(ideographicLine.summary == "\u{3000}we decided")
        #expect(ideographicLine.decisions == ["\u{3000}we decided"])

        let vertical = try notes([("\u{000B}", true)])
        #expect(vertical.summary == "\u{000B}")

        let verticalAction = try notes([("\u{000B}todo the rest", true)])
        #expect(verticalAction.summary == "\u{000B}todo the rest")
        #expect(verticalAction.actionItems == [ScribeActionItem(text: "\u{000B}todo the rest", done: false)])

        let spaced = try notes([(" \twe decided\r\n", true)])
        #expect(spaced.summary == "we decided")
        #expect(spaced.decisions == ["we decided"])

        let noBreak = try notes([("\u{00A0}Alex will send it\u{00A0}", true)])
        #expect(noBreak.summary == "Alex will send it")
        #expect(noBreak.actionItems == [ScribeActionItem(text: "Alex will send it", done: false)])

        let kept = try notes([(" \u{200B} ", true), ("  \t\n", true), ("hello", true)])
        #expect(kept.summary == "\u{200B} hello")

        let provisional = try notes([("\u{200B}", false)])
        #expect(provisional.summary.isEmpty)
        #expect(provisional.isEmpty)

        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}"] {
            let empty = try notes([(blank, true)])
            #expect(empty.summary.isEmpty)
            #expect(empty.decisions.isEmpty)
            #expect(empty.actionItems.isEmpty)
            #expect(empty.isEmpty)
        }
    }
}
