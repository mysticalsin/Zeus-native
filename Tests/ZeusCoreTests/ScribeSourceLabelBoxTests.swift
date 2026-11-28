import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the source-label trim inside `ScribeSpeaker.forSource`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe source label box")
struct ScribeSourceLabelBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeSourceLabelBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeSourceLabelBox.blankScalars.count == 5)
        #expect(ScribeSourceLabelBox.blankScalars.contains(" "))
        #expect(ScribeSourceLabelBox.blankScalars.contains("\t"))
        #expect(ScribeSourceLabelBox.blankScalars.contains("\n"))
        #expect(ScribeSourceLabelBox.blankScalars.contains("\r"))
        #expect(ScribeSourceLabelBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeSourceLabelBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeSourceLabelBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeSourceLabelBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedLabel() {
        #expect(ScribeSourceLabelBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(ScribeSourceLabelBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(ScribeSourceLabelBox.trimmedLabel("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeSourceLabelBox.trimmedLabel("\u{200B}Sam") == "\u{200B}Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel("Sam\u{200B}") == "Sam\u{200B}")
        #expect(ScribeSourceLabelBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(ScribeSourceLabelBox.trimmedLabel("") == "")
        #expect(ScribeSourceLabelBox.trimmedLabel("\u{000B}Sam") == "\u{000B}Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel("\u{3000}Sam") == "\u{3000}Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel(" \tSam\r\n") == "Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel("\u{00A0}Sam\u{00A0}") == "Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel("Sam") == "Sam")
        #expect(ScribeSourceLabelBox.trimmedLabel("Sa\u{200B}m") == "Sa\u{200B}m")
        #expect(ScribeSourceLabelBox.trimmedLabel("\n") == "")
        #expect(ScribeSourceLabelBox.trimmedLabel("\r") == "")
        #expect(ScribeSourceLabelBox.trimmedLabel("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceIsStillAParticipantLabel() {
        #expect(ScribeSpeaker.forSource(.microphone) == .you)
        #expect(ScribeSpeaker.forSource(.microphone, label: "Sam") == .you)
        #expect(ScribeSpeaker.forSource(.microphone, label: "\u{200B}") == .you)
        #expect(ScribeSpeaker.forSource(.microphone, label: " \u{200B} ") == .you)
        #expect(ScribeSpeaker.forSource(.system) == .unknown)
        #expect(ScribeSpeaker.forSource(.system, label: "Sam") == .participant("Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: " \tSam\r\n") == .participant("Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{00A0}Sam\u{00A0}") == .participant("Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{200B}") == .participant("\u{200B}"))
        #expect(ScribeSpeaker.forSource(.system, label: " \u{200B} ") == .participant("\u{200B}"))
        #expect(ScribeSpeaker.forSource(.system, label: "\t\u{200B}\n") == .participant("\u{200B}"))
        #expect(ScribeSpeaker.forSource(.system, label: "\n\u{200B}\r") == .participant("\u{200B}"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{200B}Sam") == .participant("\u{200B}Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: "Sam\u{200B}") == .participant("Sam\u{200B}"))
        #expect(ScribeSpeaker.forSource(.system, label: "Sa\u{200B}m") == .participant("Sa\u{200B}m"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{3000}") == .participant("\u{3000}"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{3000}Sam") == .participant("\u{3000}Sam"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{000B}") == .participant("\u{000B}"))
        #expect(ScribeSpeaker.forSource(.system, label: "\u{000B}Sam") == .participant("\u{000B}Sam"))
        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}", "  "] {
            #expect(ScribeSpeaker.forSource(.system, label: blank) == .unknown)
        }
    }
}
