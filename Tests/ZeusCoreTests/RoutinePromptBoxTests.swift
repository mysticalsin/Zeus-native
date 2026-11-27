import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a routine prompt. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Routine prompt box")
struct RoutinePromptBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(RoutinePromptBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(RoutinePromptBox.blankScalars.count == 5)
        #expect(RoutinePromptBox.blankScalars.contains(" "))
        #expect(RoutinePromptBox.blankScalars.contains("\t"))
        #expect(RoutinePromptBox.blankScalars.contains("\n"))
        #expect(RoutinePromptBox.blankScalars.contains("\r"))
        #expect(RoutinePromptBox.blankScalars.contains("\u{00A0}"))
        #expect(!RoutinePromptBox.blankScalars.contains("\u{200B}"))
        #expect(!RoutinePromptBox.blankScalars.contains("\u{000B}"))
        #expect(!RoutinePromptBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(RoutinePromptBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(RoutinePromptBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(RoutinePromptBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(RoutinePromptBox.trimmedText("\u{200B}hello") == "\u{200B}hello")
        #expect(RoutinePromptBox.trimmedText("hello\u{200B}") == "hello\u{200B}")
        #expect(RoutinePromptBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(RoutinePromptBox.trimmedText("") == "")
        #expect(RoutinePromptBox.trimmedText("\u{000B}hello") == "\u{000B}hello")
        #expect(RoutinePromptBox.trimmedText("\u{3000}hello") == "\u{3000}hello")
        #expect(RoutinePromptBox.trimmedText(" \thello\r\n") == "hello")
        #expect(RoutinePromptBox.trimmedText("\u{00A0}hello\u{00A0}") == "hello")
        #expect(RoutinePromptBox.trimmedText("hello\u{00A0}there") == "hello\u{00A0}there")
    }

    @Test func aZeroWidthSpaceStaysInADuePrompt() {
        let now = at("2026-10-30T10:00:00Z")
        #expect(due("\u{200B}", now: now))
        #expect(due(" \u{200B} ", now: now))
        #expect(due("\t\u{200B}\n", now: now))
        #expect(due("\u{200B}hello", now: now))
        #expect(due("hello\u{200B}", now: now))
        #expect(!due(" \t\n\r\u{00A0}", now: now))
        #expect(!due("\u{00A0}", now: now))
        #expect(!due("", now: now))
        #expect(due("\u{000B}", now: now))
        #expect(due("\u{000B}hello", now: now))
        #expect(due("\u{3000}", now: now))
        #expect(due("\u{3000}hello", now: now))
        #expect(due(" \thello\r\n", now: now))
        #expect(due("\u{00A0}hello\u{00A0}", now: now))
        #expect(due("hello", now: now))
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func due(_ prompt: String, now: Date) -> Bool {
        Routine(name: "Brief", prompt: prompt, schedule: .init(days: .daily, hour: 7, minute: 0),
                created: at("2026-10-01T00:00:00Z"), lastRun: at("2026-10-29T07:00:00Z"))
            .isDue(now: now, calendar: utc)
    }
}
