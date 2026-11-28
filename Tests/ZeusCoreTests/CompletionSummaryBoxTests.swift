import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the summary trim inside `AgentCompletion.init`.
/// These tests name the blanks. Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Completion summary box")
struct CompletionSummaryBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(CompletionSummaryBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(CompletionSummaryBox.blankScalars.count == 5)
        #expect(CompletionSummaryBox.blankScalars.contains(" "))
        #expect(CompletionSummaryBox.blankScalars.contains("\t"))
        #expect(CompletionSummaryBox.blankScalars.contains("\n"))
        #expect(CompletionSummaryBox.blankScalars.contains("\r"))
        #expect(CompletionSummaryBox.blankScalars.contains("\u{00A0}"))
        #expect(!CompletionSummaryBox.blankScalars.contains("\u{200B}"))
        #expect(!CompletionSummaryBox.blankScalars.contains("\u{000B}"))
        #expect(!CompletionSummaryBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedSummary() {
        #expect(CompletionSummaryBox.trimmedSummary("\u{200B}") == "\u{200B}")
        #expect(CompletionSummaryBox.trimmedSummary(" \u{200B} ") == "\u{200B}")
        #expect(CompletionSummaryBox.trimmedSummary("\t\u{200B}\n") == "\u{200B}")
        #expect(CompletionSummaryBox.trimmedSummary("\u{200B}Fixed") == "\u{200B}Fixed")
        #expect(CompletionSummaryBox.trimmedSummary("Fixed\u{200B}") == "Fixed\u{200B}")
        #expect(CompletionSummaryBox.trimmedSummary("Fi\u{200B}xed") == "Fi\u{200B}xed")
        #expect(CompletionSummaryBox.trimmedSummary(" \t\n\r\u{00A0}") == "")
        #expect(CompletionSummaryBox.trimmedSummary("") == "")
        #expect(CompletionSummaryBox.trimmedSummary("\u{000B}Fixed") == "\u{000B}Fixed")
        #expect(CompletionSummaryBox.trimmedSummary("\u{3000}Fixed") == "\u{3000}Fixed")
        #expect(CompletionSummaryBox.trimmedSummary(" \tFixed\r\n") == "Fixed")
        #expect(CompletionSummaryBox.trimmedSummary("\u{00A0}Fixed\u{00A0}") == "Fixed")
        #expect(CompletionSummaryBox.trimmedSummary("Fixed") == "Fixed")
        #expect(CompletionSummaryBox.trimmedSummary("\n") == "")
        #expect(CompletionSummaryBox.trimmedSummary("\r") == "")
        #expect(CompletionSummaryBox.trimmedSummary("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheCompletionSummary() {
        #expect(summary("\u{200B}") == "\u{200B}")
        #expect(summary("\u{200B}") != "Finished.")
        #expect(summary(" \u{200B} ") == "\u{200B}")
        #expect(summary("\t\u{200B}\n") == "\u{200B}")
        #expect(summary("\u{200B}Fixed") == "\u{200B}Fixed")
        #expect(summary("Fixed\u{200B}") == "Fixed\u{200B}")
        #expect(summary("Fi\u{200B}xed") == "Fi\u{200B}xed")
        #expect(summary("\u{3000}Fixed") == "\u{3000}Fixed")
        #expect(summary("\u{3000}Fixed") != "Fixed")
        #expect(summary("\u{000B}Fixed") == "Fixed")
        #expect(summary("\u{000B}") == "Finished.")
        #expect(summary(" \tFixed\r\n") == "Fixed")
        #expect(summary("\u{00A0}Fixed\u{00A0}") == "Fixed")
        #expect(summary("Fixed") == "Fixed")
        #expect(summary("\n") == "Finished.")
        #expect(summary("\r") == "Finished.")
        #expect(summary("\n\u{200B}\r") == "\u{200B}")
        #expect(summary("\n\u{200B}\r") != "Finished.")
        #expect(summary("  \n \n ") == "Finished.")
        #expect(summary("  Fixed it.  ") == "Fixed it.")
        #expect(summary("All tests pass.\nCommitted.") == "All tests pass. Committed.")
        #expect(summary(nil) == "Finished.")
        #expect(summary(" \t\n\r\u{00A0}") == "Finished.")
        let plan = JSONValue.object(["plan": .string("\u{200B}")])
        #expect(AgentPlan.text(plan) == nil)
        #expect(AgentPlan.text(plan) != "\u{200B}")
        #expect(AgentPlan.feedbackMessage("\u{200B}") == "The user did not approve this plan yet. Keep planning and ask what to change.")
        #expect(!AgentPlan.feedbackMessage("\u{200B}").contains("\u{200B}"))
    }

    private func summary(_ text: String?) -> String {
        AgentCompletion(sessionID: "s", agent: "a", project: "p", summary: text, startedAt: nil).summary
    }
}
