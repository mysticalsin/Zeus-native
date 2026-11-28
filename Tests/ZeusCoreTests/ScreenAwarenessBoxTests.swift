import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in an accessibility summary. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Screen awareness summary box")
struct ScreenAwarenessBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScreenAwarenessBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScreenAwarenessBox.blankScalars.count == 5)
        #expect(ScreenAwarenessBox.blankScalars.contains(" "))
        #expect(ScreenAwarenessBox.blankScalars.contains("\t"))
        #expect(ScreenAwarenessBox.blankScalars.contains("\n"))
        #expect(ScreenAwarenessBox.blankScalars.contains("\r"))
        #expect(ScreenAwarenessBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScreenAwarenessBox.blankScalars.contains("\u{200B}"))
        #expect(!ScreenAwarenessBox.blankScalars.contains("\u{000B}"))
        #expect(!ScreenAwarenessBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedSummary() {
        #expect(ScreenAwarenessBox.trimmedSummary("\u{200B}") == "\u{200B}")
        #expect(ScreenAwarenessBox.trimmedSummary(" \u{200B} ") == "\u{200B}")
        #expect(ScreenAwarenessBox.trimmedSummary("\t\u{200B}\n") == "\u{200B}")
        #expect(ScreenAwarenessBox.trimmedSummary("\u{200B}Tokyo") == "\u{200B}Tokyo")
        #expect(ScreenAwarenessBox.trimmedSummary("Tokyo\u{200B}") == "Tokyo\u{200B}")
        #expect(ScreenAwarenessBox.trimmedSummary(" \t\n\r\u{00A0}") == "")
        #expect(ScreenAwarenessBox.trimmedSummary("") == "")
        #expect(ScreenAwarenessBox.trimmedSummary("\u{000B}Tokyo") == "\u{000B}Tokyo")
        #expect(ScreenAwarenessBox.trimmedSummary("\u{3000}Tokyo") == "\u{3000}Tokyo")
        #expect(ScreenAwarenessBox.trimmedSummary(" \tTokyo\r\n") == "Tokyo")
        #expect(ScreenAwarenessBox.trimmedSummary("\u{00A0}Tokyo\u{00A0}") == "Tokyo")
        #expect(ScreenAwarenessBox.trimmedSummary("Button") == "Button")
    }

    @Test func aZeroWidthSpaceStaysInTheScreenPlan() {
        #expect(ScreenAwarenessBox.trimmedSummary(" \u{200B}Tokyo ") == "\u{200B}Tokyo")
        let kept = ScreenAwareness.plan(transcript: "hello", axSummary: "\u{200B}", tab: nil)
        #expect(kept.promptPrefix == "Front context. axTokens=1.")
        #expect(kept.axTokenEstimate == 1)
        #expect(!kept.needsCapture)
        #expect(!kept.preferPixels)
        let dropped = ScreenAwareness.plan(transcript: "hello", axSummary: " \t\n\r\u{00A0}", tab: nil)
        #expect(dropped.promptPrefix == "")
        #expect(!dropped.needsCapture)
        let named = ScreenAwareness.plan(transcript: "hello", axSummary: "  Button  ", tab: nil)
        #expect(named.promptPrefix == "Front context. axTokens=1.")
        let question = ScreenAwareness.plan(transcript: "what's on my screen", axSummary: "  Panel  ", tab: nil)
        #expect(question.promptPrefix.contains("Screen question"))
        #expect(question.promptPrefix.contains("axTokens="))
        #expect(question.needsCapture)
        let ideographic = ScreenAwareness.plan(transcript: "hello", axSummary: "\u{3000}Tokyo", tab: nil)
        #expect(ideographic.promptPrefix.contains("Front context"))
        let vertical = ScreenAwareness.plan(transcript: "hello", axSummary: "\u{000B}Tokyo", tab: nil)
        #expect(vertical.promptPrefix.contains("Front context"))
        let none = ScreenAwareness.plan(transcript: "hello", axSummary: nil, tab: nil)
        #expect(none.promptPrefix == "")
    }
}
