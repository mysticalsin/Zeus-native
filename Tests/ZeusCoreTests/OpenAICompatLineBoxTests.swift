import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on an OpenAI-compatible line. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("OpenAI-compatible line box")
struct OpenAICompatLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(OpenAICompatLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(OpenAICompatLineBox.blankScalars.count == 5)
        #expect(OpenAICompatLineBox.blankScalars.contains(" "))
        #expect(OpenAICompatLineBox.blankScalars.contains("\t"))
        #expect(OpenAICompatLineBox.blankScalars.contains("\n"))
        #expect(OpenAICompatLineBox.blankScalars.contains("\r"))
        #expect(OpenAICompatLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!OpenAICompatLineBox.blankScalars.contains("\u{200B}"))
        #expect(!OpenAICompatLineBox.blankScalars.contains("\u{000B}"))
        #expect(!OpenAICompatLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedLine() {
        #expect(OpenAICompatLineBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(OpenAICompatLineBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(OpenAICompatLineBox.trimmedLine("\t\u{200B}\n") == "\u{200B}")
        #expect(OpenAICompatLineBox.trimmedLine("\u{200B}data:") == "\u{200B}data:")
        #expect(OpenAICompatLineBox.trimmedLine("data:\u{200B}") == "data:\u{200B}")
        #expect(OpenAICompatLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        #expect(OpenAICompatLineBox.trimmedLine("") == "")
        #expect(OpenAICompatLineBox.trimmedLine("\u{000B}data:") == "\u{000B}data:")
        #expect(OpenAICompatLineBox.trimmedLine("\u{3000}data:") == "\u{3000}data:")
        #expect(OpenAICompatLineBox.trimmedLine(" \tdata:\r\n") == "data:")
        #expect(OpenAICompatLineBox.trimmedLine("\u{00A0}data:\u{00A0}") == "data:")
        #expect(OpenAICompatLineBox.trimmedLine("data:") == "data:")
    }

    @Test func aZeroWidthSpaceStaysOnTheParsedLine() {
        #expect(OpenAICompat.parse(chunk: "\u{200B}data: [DONE]") == [])
        #expect(OpenAICompat.parse(chunk: "data:\u{200B}[DONE]") == [])
        #expect(OpenAICompat.parse(chunk: "data: [DONE]\u{200B}") == [])
        #expect(OpenAICompat.parse(chunk: "\u{200B}") == [])
        #expect(OpenAICompat.parse(chunk: " \t\n\r\u{00A0}") == [])
        #expect(OpenAICompat.parse(chunk: "\u{000B}data: [DONE]") == [])
        #expect(OpenAICompat.parse(chunk: "\u{3000}data: [DONE]") == [])
        #expect(OpenAICompat.parse(chunk: "  data: [DONE]  ") == [.done])
        #expect(OpenAICompat.parse(chunk: "\t data: [DONE]\n") == [.done])
        #expect(OpenAICompat.parse(chunk: "\u{00A0}data: [DONE]\u{00A0}") == [.done])
        #expect(OpenAICompat.parse(chunk: "\ndata: [DONE]\r") == [.done])
        #expect(OpenAICompat.parse(chunk: "data: [DONE]") == [.done])
        let chunk = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" there"}}]}

        data: [DONE]

        """
        #expect(OpenAICompat.parse(chunk: chunk) == [.delta("Hello"), .delta(" there"), .done])
        #expect(OpenAICompat.parse(chunk: #"{"error":{"message":"nope"}}"#) == [.failure("nope")])
        #expect(OpenAICompat.parse(chunk: "\u{00A0}{\"error\":{\"message\":\"nope\"}}") == [.failure("nope")])
    }
}
