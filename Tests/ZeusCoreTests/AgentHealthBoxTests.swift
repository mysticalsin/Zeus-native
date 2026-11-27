import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in an agent failure detail. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Agent health box")
struct AgentHealthBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AgentHealthBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AgentHealthBox.blankScalars.count == 5)
        #expect(AgentHealthBox.blankScalars.contains(" "))
        #expect(AgentHealthBox.blankScalars.contains("\t"))
        #expect(AgentHealthBox.blankScalars.contains("\n"))
        #expect(AgentHealthBox.blankScalars.contains("\r"))
        #expect(AgentHealthBox.blankScalars.contains("\u{00A0}"))
        #expect(!AgentHealthBox.blankScalars.contains("\u{200B}"))
        #expect(!AgentHealthBox.blankScalars.contains("\u{000B}"))
        #expect(!AgentHealthBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTrimmedDetail() {
        #expect(AgentHealthBox.trimmedDetail("\u{200B}") == "\u{200B}")
        #expect(AgentHealthBox.trimmedDetail(" \u{200B} ") == "\u{200B}")
        #expect(AgentHealthBox.trimmedDetail("\t\u{200B}\n") == "\u{200B}")
        #expect(AgentHealthBox.trimmedDetail("\u{200B}halt") == "\u{200B}halt")
        #expect(AgentHealthBox.trimmedDetail("halt\u{200B}") == "halt\u{200B}")
        #expect(AgentHealthBox.trimmedDetail(" \t\n\r\u{00A0}") == "")
        #expect(AgentHealthBox.trimmedDetail("") == "")
        #expect(AgentHealthBox.trimmedDetail("\u{000B}halt") == "\u{000B}halt")
        #expect(AgentHealthBox.trimmedDetail("\u{3000}halt") == "\u{3000}halt")
        #expect(AgentHealthBox.trimmedDetail(" \thalt\r\n") == "halt")
        #expect(AgentHealthBox.trimmedDetail("\u{00A0}halt\u{00A0}") == "halt")
        #expect(AgentHealthBox.trimmedDetail("too\u{00A0}many") == "too\u{00A0}many")
    }

    @Test func aZeroWidthSpaceStaysInTheFailureReason() {
        #expect(AgentFailureParser.reason(code: nil, detail: "\u{200B}") == "\u{200B}")
        #expect(AgentFailureParser.reason(code: nil, detail: " \u{200B} ") == "\u{200B}")
        #expect(AgentFailureParser.reason(code: nil, detail: "\u{000B}halt") == "\u{000B}halt")
        #expect(AgentFailureParser.reason(code: nil, detail: "\u{3000}halt") == "\u{3000}halt")
        #expect(AgentFailureParser.reason(code: nil, detail: " \t\n\r\u{00A0}") == "The agent stopped with an error")
        #expect(AgentFailureParser.reason(code: "rate_limit", detail: "\u{200B}") == "Rate limit reached: \u{200B}")
        #expect(AgentFailureParser.reason(code: "rate_limit", detail: " \u{00A0}429\n") == "Rate limit reached: 429")
        #expect(AgentFailureParser.reason(code: "rate_limit", detail: " \t\n\r\u{00A0}") == "Rate limit reached")
        #expect(AgentFailureParser.reason(code: nil, detail: "API Error: 500\nretry later") == "API Error: 500 retry later")
        let payload = JSONValue.object(["error_details": .string("\u{200B}")])
        #expect(AgentFailureParser.reason(from: payload) == "\u{200B}")
        let blanks = JSONValue.object(["message": .string(" \t\n\r\u{00A0}")])
        #expect(AgentFailureParser.reason(from: blanks) == "The agent stopped with an error")
    }
}
