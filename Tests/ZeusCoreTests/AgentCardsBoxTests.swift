import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in an agent plan. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Agent cards box")
struct AgentCardsBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AgentCardsBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AgentCardsBox.blankScalars.count == 5)
        #expect(AgentCardsBox.blankScalars.contains(" "))
        #expect(AgentCardsBox.blankScalars.contains("\t"))
        #expect(AgentCardsBox.blankScalars.contains("\n"))
        #expect(AgentCardsBox.blankScalars.contains("\r"))
        #expect(AgentCardsBox.blankScalars.contains("\u{00A0}"))
        #expect(!AgentCardsBox.blankScalars.contains("\u{200B}"))
        #expect(!AgentCardsBox.blankScalars.contains("\u{000B}"))
        #expect(!AgentCardsBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATrimmedPlan() {
        #expect(AgentCardsBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(AgentCardsBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(AgentCardsBox.trimmed("\t\u{200B}\n") == "\u{200B}")
        #expect(AgentCardsBox.trimmed("\u{200B}plan") == "\u{200B}plan")
        #expect(AgentCardsBox.trimmed("plan\u{200B}") == "plan\u{200B}")
        #expect(AgentCardsBox.trimmed(" \t\n\r\u{00A0}") == "")
        #expect(AgentCardsBox.trimmed("") == "")
        #expect(AgentCardsBox.trimmed("\u{000B}plan") == "\u{000B}plan")
        #expect(AgentCardsBox.trimmed("\u{3000}plan") == "\u{3000}plan")
        #expect(AgentCardsBox.trimmed(" \tplan\r\n") == "plan")
        #expect(AgentCardsBox.trimmed("\u{00A0}plan\u{00A0}") == "plan")
        #expect(AgentCardsBox.trimmed("too\u{00A0}many") == "too\u{00A0}many")
        #expect(AgentCardsBox.trimmed("  ## Plan\n1. Do it  ") == "## Plan\n1. Do it")
    }

    @Test func aZeroWidthSpaceStaysInThePlanAndTheFeedback() {
        #expect(AgentPlan.text(.object(["plan": .string("\u{200B}")])) == "\u{200B}")
        #expect(AgentPlan.text(.object(["plan": .string(" \u{200B} ")])) == "\u{200B}")
        #expect(AgentPlan.text(.object(["plan": .string("\u{000B}plan")])) == "\u{000B}plan")
        #expect(AgentPlan.text(.object(["plan": .string("\u{3000}plan")])) == "\u{3000}plan")
        #expect(AgentPlan.text(.object(["plan": .string(" \t\n\r\u{00A0}")])) == nil)
        #expect(AgentPlan.text(.object(["plan": .string("  ## Plan\n1. Do it  ")])) == "## Plan\n1. Do it")
        #expect(AgentPlan.text(.object(["plan": .string("\u{00A0}## Plan\u{00A0}")])) == "## Plan")
        #expect(AgentPlan.feedbackMessage("\u{200B}").hasSuffix("feedback: \u{200B}"))
        #expect(AgentPlan.feedbackMessage(" \u{200B} ").hasSuffix("feedback: \u{200B}"))
        #expect(AgentPlan.feedbackMessage("\u{000B}").hasSuffix("feedback: \u{000B}"))
        #expect(AgentPlan.feedbackMessage("\u{3000}").hasSuffix("feedback: \u{3000}"))
        #expect(AgentPlan.feedbackMessage(" ").contains("Keep planning"))
        #expect(AgentPlan.feedbackMessage(" \t\n\r\u{00A0}").contains("Keep planning"))
        #expect(AgentPlan.feedbackMessage("use SQLite").hasSuffix("feedback: use SQLite"))
        #expect(AgentPlan.feedbackMessage("\u{00A0}use SQLite\u{00A0}").hasSuffix("feedback: use SQLite"))
    }
}
