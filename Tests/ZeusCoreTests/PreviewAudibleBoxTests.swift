import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the audible trim inside `UltronVoicePlan.previewPlaysAudio`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Preview audible box")
struct PreviewAudibleBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PreviewAudibleBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PreviewAudibleBox.blankScalars.count == 5)
        #expect(PreviewAudibleBox.blankScalars.contains(" "))
        #expect(PreviewAudibleBox.blankScalars.contains("\t"))
        #expect(PreviewAudibleBox.blankScalars.contains("\n"))
        #expect(PreviewAudibleBox.blankScalars.contains("\r"))
        #expect(PreviewAudibleBox.blankScalars.contains("\u{00A0}"))
        #expect(!PreviewAudibleBox.blankScalars.contains("\u{200B}"))
        #expect(!PreviewAudibleBox.blankScalars.contains("\u{000B}"))
        #expect(!PreviewAudibleBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedAudible() {
        #expect(PreviewAudibleBox.trimmedAudible("\u{200B}") == "\u{200B}")
        #expect(PreviewAudibleBox.trimmedAudible(" \u{200B} ") == "\u{200B}")
        #expect(PreviewAudibleBox.trimmedAudible("\t\u{200B}\n") == "\u{200B}")
        #expect(PreviewAudibleBox.trimmedAudible("\u{200B}1") == "\u{200B}1")
        #expect(PreviewAudibleBox.trimmedAudible("1\u{200B}") == "1\u{200B}")
        #expect(PreviewAudibleBox.trimmedAudible(" \t\n\r\u{00A0}") == "")
        #expect(PreviewAudibleBox.trimmedAudible("") == "")
        #expect(PreviewAudibleBox.trimmedAudible("\u{000B}1") == "\u{000B}1")
        #expect(PreviewAudibleBox.trimmedAudible("\u{3000}1") == "\u{3000}1")
        #expect(PreviewAudibleBox.trimmedAudible(" \t1\r\n") == "1")
        #expect(PreviewAudibleBox.trimmedAudible("\u{00A0}1\u{00A0}") == "1")
        #expect(PreviewAudibleBox.trimmedAudible("1") == "1")
        #expect(PreviewAudibleBox.trimmedAudible("1\u{200B}0") == "1\u{200B}0")
        #expect(PreviewAudibleBox.trimmedAudible("\n") == "")
        #expect(PreviewAudibleBox.trimmedAudible("\r") == "")
        #expect(PreviewAudibleBox.trimmedAudible("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnThePreviewDecision() {
        #expect(plays("\u{200B}"))
        #expect(plays("\u{200B}") != false)
        #expect(plays(" \u{200B} "))
        #expect(plays("\t\u{200B}\n"))
        #expect(plays("\u{200B}1"))
        #expect(plays("1\u{200B}"))
        #expect(plays("false\u{200B}"))
        #expect(plays("false\u{200B}") != false)
        #expect(plays("\u{200B}false"))
        #expect(plays("\n\u{200B}\r"))
        #expect(plays("\u{3000}"))
        #expect(plays("\u{3000}") != false)
        #expect(plays("\u{000B}"))
        #expect(plays("\u{000B}") != false)
        #expect(!plays("\u{00A0}"))
        #expect(!plays(" \t\n\r\u{00A0}"))
        #expect(!plays("\n"))
        #expect(!plays("\r"))
        #expect(!plays(nil))
        #expect(!plays(""))
        #expect(!plays("0"))
        #expect(!plays(" 0 "))
        #expect(!plays("\u{00A0}0\u{00A0}"))
        #expect(!plays("false"))
        #expect(!plays(" false "))
        #expect(!plays(" FALSE "))
        #expect(!plays("\u{00A0}false\u{00A0}"))
        #expect(plays("1"))
        #expect(plays(" 1 "))
        #expect(plays("\u{00A0}1\u{00A0}"))
        #expect(plays(" \t1\r\n"))
        #expect(plays("true"))
    }

    private func plays(_ audibleOK: String?) -> Bool {
        UltronVoicePlan.previewPlaysAudio(audibleOK: audibleOK)
    }
}
