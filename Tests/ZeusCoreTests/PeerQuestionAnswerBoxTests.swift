import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the answer trim inside `PeerQuestionSelection.chose`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Peer question answer box")
struct PeerQuestionAnswerBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PeerQuestionAnswerBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PeerQuestionAnswerBox.blankScalars.count == 5)
        #expect(PeerQuestionAnswerBox.blankScalars.contains(" "))
        #expect(PeerQuestionAnswerBox.blankScalars.contains("\t"))
        #expect(PeerQuestionAnswerBox.blankScalars.contains("\n"))
        #expect(PeerQuestionAnswerBox.blankScalars.contains("\r"))
        #expect(PeerQuestionAnswerBox.blankScalars.contains("\u{00A0}"))
        #expect(!PeerQuestionAnswerBox.blankScalars.contains("\u{200B}"))
        #expect(!PeerQuestionAnswerBox.blankScalars.contains("\u{000B}"))
        #expect(!PeerQuestionAnswerBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedAnswer() {
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\u{200B}") == "\u{200B}")
        #expect(PeerQuestionAnswerBox.trimmedAnswer(" \u{200B} ") == "\u{200B}")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\t\u{200B}\n") == "\u{200B}")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\u{200B}Yes") == "\u{200B}Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("Yes\u{200B}") == "Yes\u{200B}")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("Ye\u{200B}s") == "Ye\u{200B}s")
        #expect(PeerQuestionAnswerBox.trimmedAnswer(" \t\n\r\u{00A0}") == "")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("") == "")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\u{000B}Yes") == "\u{000B}Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\u{3000}Yes") == "\u{3000}Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer(" \tYes\r\n") == "Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\u{00A0}Yes\u{00A0}") == "Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("Yes") == "Yes")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\n") == "")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\r") == "")
        #expect(PeerQuestionAnswerBox.trimmedAnswer("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStillCountsAsAPeerAnswer() {
        #expect(chose("\u{200B}"))
        #expect(chose(" \u{200B} "))
        #expect(chose("\t\u{200B}\n"))
        #expect(chose("\u{200B}Yes"))
        #expect(chose("Yes\u{200B}"))
        #expect(chose("Ye\u{200B}s"))
        #expect(chose("\n\u{200B}\r"))
        #expect(chose("\u{3000}"))
        #expect(chose("\u{3000}Yes"))
        #expect(chose("\u{000B}"))
        #expect(chose("\u{000B}Yes"))
        #expect(chose("Yes"))
        #expect(chose("A"))
        #expect(chose(" \tYes\r\n"))
        #expect(chose("\u{00A0}Yes\u{00A0}"))
        #expect(chose("  ") == false)
        #expect(chose(" \t\n\r\u{00A0}") == false)
        #expect(chose("\n") == false)
        #expect(chose("\r") == false)
        #expect(chose("") == false)
        #expect(chose("   ") == false)
        #expect(chose("\u{00A0}") == false)
        #expect(PeerQuestionSelection.chose(detail: #"{"answers":{"Q":"A"}}"#))
        #expect(PeerQuestionSelection.chose(detail: #"{"answers":{"Q":"  "}}"#) == false)
        #expect(PeerQuestionSelection.chose(detail: "User has not answered yet") == false)
        #expect(PeerQuestionSelection.chose(detail: nil) == false)
    }

    private func chose(_ answer: String) -> Bool {
        let payload: [String: [String: String]] = ["answers": ["Q": answer]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let detail = String(data: data, encoding: .utf8) else { return false }
        return PeerQuestionSelection.chose(detail: detail)
    }
}
