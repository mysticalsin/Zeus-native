import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a morning brief name. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Morning brief name box")
struct MorningBriefNameBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(MorningBriefNameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(MorningBriefNameBox.blankScalars.count == 5)
        #expect(MorningBriefNameBox.blankScalars.contains(" "))
        #expect(MorningBriefNameBox.blankScalars.contains("\t"))
        #expect(MorningBriefNameBox.blankScalars.contains("\n"))
        #expect(MorningBriefNameBox.blankScalars.contains("\r"))
        #expect(MorningBriefNameBox.blankScalars.contains("\u{00A0}"))
        #expect(!MorningBriefNameBox.blankScalars.contains("\u{200B}"))
        #expect(!MorningBriefNameBox.blankScalars.contains("\u{000B}"))
        #expect(!MorningBriefNameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedName() {
        #expect(MorningBriefNameBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(MorningBriefNameBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(MorningBriefNameBox.trimmedName("\t\u{200B}\n") == "\u{200B}")
        #expect(MorningBriefNameBox.trimmedName("\u{200B}Tony") == "\u{200B}Tony")
        #expect(MorningBriefNameBox.trimmedName("Tony\u{200B}") == "Tony\u{200B}")
        #expect(MorningBriefNameBox.trimmedName(" \t\n\r\u{00A0}") == "")
        #expect(MorningBriefNameBox.trimmedName("") == "")
        #expect(MorningBriefNameBox.trimmedName("\u{000B}Tony") == "\u{000B}Tony")
        #expect(MorningBriefNameBox.trimmedName("\u{3000}Tony") == "\u{3000}Tony")
        #expect(MorningBriefNameBox.trimmedName(" \tTony\r\n") == "Tony")
        #expect(MorningBriefNameBox.trimmedName("\u{00A0}Tony\u{00A0}") == "Tony")
        #expect(MorningBriefNameBox.trimmedName("Tony\u{00A0}Walteur") == "Tony\u{00A0}Walteur")
    }

    @Test func aZeroWidthSpaceStaysInTheMorningGreeting() {
        let zwsp = "\u{200B}"
        #expect(greeting(zwsp) == "Good morning, \(zwsp)")
        #expect(greeting(" \(zwsp) ") == "Good morning, \(zwsp)")
        #expect(greeting("\t\(zwsp)\n") == "Good morning, \(zwsp)")
        #expect(greeting("\(zwsp) Tony") == "Good morning, \(zwsp)")
        #expect(greeting(" \t\n\r\u{00A0}") == "Good morning")
        #expect(greeting("") == "Good morning")
        #expect(greeting(nil) == "Good morning")
        #expect(greeting("\u{000B}") == "Good morning, \u{000B}")
        #expect(greeting("\u{3000}") == "Good morning, \u{3000}")
        #expect(greeting("\u{00A0}Tony Walteur\u{00A0}") == "Good morning, Tony")
        #expect(greeting(" \tTony\r\n") == "Good morning, Tony")
        #expect(greeting("Tony\u{00A0}Walteur") == "Good morning, Tony\u{00A0}Walteur")
    }

    private func greeting(_ name: String?) -> String {
        MorningBrief.build(now: morning, events: [], todos: [], name: name, calendar: utc).greeting
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var morning: Date { ISO8601DateFormatter().date(from: "2026-11-02T08:10:00Z")! }
}
