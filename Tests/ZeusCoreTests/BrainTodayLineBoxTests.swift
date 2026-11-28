import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a brain-today line. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Brain today line box")
struct BrainTodayLineBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BrainTodayLineBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BrainTodayLineBox.blankScalars.count == 5)
        #expect(BrainTodayLineBox.blankScalars.contains(" "))
        #expect(BrainTodayLineBox.blankScalars.contains("\t"))
        #expect(BrainTodayLineBox.blankScalars.contains("\n"))
        #expect(BrainTodayLineBox.blankScalars.contains("\r"))
        #expect(BrainTodayLineBox.blankScalars.contains("\u{00A0}"))
        #expect(!BrainTodayLineBox.blankScalars.contains("\u{200B}"))
        #expect(!BrainTodayLineBox.blankScalars.contains("\u{000B}"))
        #expect(!BrainTodayLineBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedLine() {
        #expect(BrainTodayLineBox.trimmedLine("\u{200B}") == "\u{200B}")
        #expect(BrainTodayLineBox.trimmedLine(" \u{200B} ") == "\u{200B}")
        #expect(BrainTodayLineBox.trimmedLine("\t\u{200B}\n") == "\u{200B}")
        #expect(BrainTodayLineBox.trimmedLine("\u{200B}- [ ] Ghost") == "\u{200B}- [ ] Ghost")
        #expect(BrainTodayLineBox.trimmedLine("- [ ] Call\u{200B}") == "- [ ] Call\u{200B}")
        #expect(BrainTodayLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        #expect(BrainTodayLineBox.trimmedLine("") == "")
        #expect(BrainTodayLineBox.trimmedLine("\u{000B}- [ ] Vertical") == "\u{000B}- [ ] Vertical")
        #expect(BrainTodayLineBox.trimmedLine("\u{3000}- [ ] Wide") == "\u{3000}- [ ] Wide")
        #expect(BrainTodayLineBox.trimmedLine(" \t- [ ] Kept\r\n") == "- [ ] Kept")
        #expect(BrainTodayLineBox.trimmedLine("\u{00A0}- [ ] Kept\u{00A0}") == "- [ ] Kept")
        #expect(BrainTodayLineBox.trimmedLine("- [ ] Call Anna") == "- [ ] Call Anna")
    }

    @Test func aZeroWidthSpaceStaysOnTheScannedLine() throws {
        #expect(BrainTodayLineBox.trimmedLine(" \u{200B}- [ ] Ghost") == "\u{200B}- [ ] Ghost")
        #expect(BrainTodayLineBox.trimmedLine("  - [ ] Call Anna  ") == "- [ ] Call Anna")
        #expect(BrainTodayLineBox.trimmedLine(" \t\n\r\u{00A0}") == "")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brain-today-line-\(UUID().uuidString)")
        let project = root.appendingPathComponent("01_Projects/Soul", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try """
        \u{200B}- [ ] Ghost
        - [ ] TASK-0001 Low thing #todo #priority/low
        - [x] Done thing
        - [ ] TASK-0002 Big thing #todo #priority/high
        - [ ] Blocked thing #blocked
        - [ ] Call Anna 📅 2026-10-31
        \u{3000}- [ ] Wide
        \u{000B}- [ ] Vertical
         \t\u{00A0}- [ ] Kept
        """.write(to: project.appendingPathComponent("01 - Tasks.md"), atomically: true, encoding: .utf8)
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 31
        parts.hour = 12
        let today = try #require(Calendar(identifier: .gregorian).date(from: parts))
        let tasks = BrainToday.scan(root: root, today: today)
        #expect(tasks.map(\.title) == ["Call Anna", "Big thing", "Low thing", "Kept"])
        #expect(tasks.first?.dueToday == true)
        #expect(tasks.first?.project == "Soul")
        #expect(!tasks.map(\.title).contains("Ghost"))
        #expect(!tasks.map(\.title).contains("Wide"))
        #expect(!tasks.map(\.title).contains("Vertical"))
    }
}
