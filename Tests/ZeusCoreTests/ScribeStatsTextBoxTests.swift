import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the segment-text trim inside `ScribeSpeakerStats.init`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe stats text box")
struct ScribeStatsTextBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeStatsTextBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeStatsTextBox.blankScalars.count == 5)
        #expect(ScribeStatsTextBox.blankScalars.contains(" "))
        #expect(ScribeStatsTextBox.blankScalars.contains("\t"))
        #expect(ScribeStatsTextBox.blankScalars.contains("\n"))
        #expect(ScribeStatsTextBox.blankScalars.contains("\r"))
        #expect(ScribeStatsTextBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeStatsTextBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeStatsTextBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeStatsTextBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedText() {
        #expect(ScribeStatsTextBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(ScribeStatsTextBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(ScribeStatsTextBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeStatsTextBox.trimmedText("\u{200B}hello") == "\u{200B}hello")
        #expect(ScribeStatsTextBox.trimmedText("hello\u{200B}") == "hello\u{200B}")
        #expect(ScribeStatsTextBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(ScribeStatsTextBox.trimmedText("") == "")
        #expect(ScribeStatsTextBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(ScribeStatsTextBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(ScribeStatsTextBox.trimmedText(" \thello\r\n") == "hello")
        #expect(ScribeStatsTextBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(ScribeStatsTextBox.trimmedText("hello") == "hello")
        #expect(ScribeStatsTextBox.trimmedText("hel\u{200B}lo") == "hel\u{200B}lo")
        #expect(ScribeStatsTextBox.trimmedText("\n") == "")
        #expect(ScribeStatsTextBox.trimmedText("\r") == "")
        #expect(ScribeStatsTextBox.trimmedText("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStillCountsAsTalk() {
        func stats(_ text: String, end: TimeInterval = 2) -> ScribeSpeakerStats {
            ScribeSpeakerStats(segments: [
                ScribeTranscriptSegment(
                    id: "a", session: ScribeSessionID(), speaker: .you,
                    start: 0, end: end, text: text, isFinal: true
                ),
            ])
        }

        let zero = stats("\u{200B}")
        #expect(zero.speakers.count == 1)
        #expect(zero.speakers.first?.speaker == .you)
        #expect(zero.speakers.first?.segmentCount == 1)
        #expect(zero.speakers.first?.talkSeconds == 2)
        #expect(zero.speakers.first?.share == 1)
        #expect(zero.isWorthShowing)
        #expect(zero.totalTalkSeconds == 2)

        let padded = stats(" \u{200B} ")
        #expect(padded.speakers.count == 1)
        #expect(padded.speakers.first?.segmentCount == 1)
        #expect(padded.speakers.first?.talkSeconds == 2)

        let between = stats("\n\u{200B}\r")
        #expect(between.speakers.count == 1)
        #expect(between.speakers.first?.talkSeconds == 2)

        let leading = stats("\u{200B}hello")
        #expect(leading.speakers.count == 1)
        #expect(leading.speakers.first?.segmentCount == 1)
        #expect(leading.speakers.first?.talkSeconds == 2)

        let trailing = stats("hello\u{200B}")
        #expect(trailing.speakers.count == 1)
        #expect(trailing.speakers.first?.talkSeconds == 2)

        let inside = stats("hel\u{200B}lo")
        #expect(inside.speakers.count == 1)
        #expect(inside.speakers.first?.talkSeconds == 2)

        let ideographic = stats("\u{3000}")
        #expect(ideographic.speakers.count == 1)
        #expect(ideographic.speakers.first?.segmentCount == 1)
        #expect(ideographic.speakers.first?.talkSeconds == 2)

        let ideographicText = stats("\u{3000}hello")
        #expect(ideographicText.speakers.count == 1)
        #expect(ideographicText.speakers.first?.talkSeconds == 2)

        let vertical = stats("\u{000B}")
        #expect(vertical.speakers.count == 1)
        #expect(vertical.speakers.first?.segmentCount == 1)
        #expect(vertical.speakers.first?.talkSeconds == 2)

        let verticalText = stats("\u{000B}hello")
        #expect(verticalText.speakers.count == 1)
        #expect(verticalText.speakers.first?.talkSeconds == 2)

        let spaced = stats(" \thello\r\n")
        #expect(spaced.speakers.count == 1)
        #expect(spaced.speakers.first?.talkSeconds == 2)
        #expect(spaced.speakers.first?.speaker == .you)

        let noBreak = stats("\u{00A0}hello\u{00A0}")
        #expect(noBreak.speakers.count == 1)
        #expect(noBreak.speakers.first?.talkSeconds == 2)

        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}"] {
            let empty = stats(blank)
            #expect(empty.speakers.isEmpty)
            #expect(!empty.isWorthShowing)
            #expect(empty.totalTalkSeconds == 0)
        }
    }
}
