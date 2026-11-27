import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a to-do title. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("To-do box")
struct TodoBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TodoBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TodoBox.blankScalars.count == 5)
        #expect(TodoBox.blankScalars.contains(" "))
        #expect(TodoBox.blankScalars.contains("\t"))
        #expect(TodoBox.blankScalars.contains("\n"))
        #expect(TodoBox.blankScalars.contains("\r"))
        #expect(TodoBox.blankScalars.contains("\u{00A0}"))
        #expect(!TodoBox.blankScalars.contains("\u{200B}"))
        #expect(!TodoBox.blankScalars.contains("\u{000B}"))
        #expect(!TodoBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInATrimmedTitle() {
        #expect(TodoBox.trimmed("\u{200B}") == "\u{200B}")
        #expect(TodoBox.trimmed(" \u{200B} ") == "\u{200B}")
        #expect(TodoBox.trimmed("\t\u{200B}\n") == "\u{200B}")
        #expect(TodoBox.trimmed("\u{200B}milk") == "\u{200B}milk")
        #expect(TodoBox.trimmed("milk\u{200B}") == "milk\u{200B}")
        #expect(TodoBox.trimmed(" \t\n\r\u{00A0}") == "")
        #expect(TodoBox.trimmed("") == "")
        #expect(TodoBox.trimmed("\u{000B}milk") == "\u{000B}milk")
        #expect(TodoBox.trimmed("\u{3000}milk") == "\u{3000}milk")
        #expect(TodoBox.trimmed(" \tmilk\r\n") == "milk")
        #expect(TodoBox.trimmed("\u{00A0}milk\u{00A0}") == "milk")
        #expect(TodoBox.trimmed("too\u{00A0}many") == "too\u{00A0}many")
    }

    @Test func aZeroWidthSpaceStaysAsAToDoTitle() {
        var list = TodoList()
        let kept = list.add("\u{200B}")
        #expect(kept?.title == "\u{200B}")
        #expect(list.add(" \u{200B} ")?.title == "\u{200B}")
        #expect(list.add(" \t\n\r\u{00A0}") == nil)
        #expect(list.add("  ") == nil)
        #expect(list.add("") == nil)
        #expect(list.add(" \tmilk\r\n")?.title == "milk")
        #expect(list.add("\u{00A0}milk\u{00A0}")?.title == "milk")
        #expect(list.add("\u{000B}milk")?.title == "\u{000B}milk")
        #expect(list.add("\u{3000}milk")?.title == "\u{3000}milk")
        let id = list.items[0].id
        list.rename(id, " \u{200B} ")
        #expect(list.items[0].title == "\u{200B}")
        list.rename(id, " \t\n\r\u{00A0}")
        #expect(list.items[0].title == "\u{200B}")
        list.rename(id, "\u{00A0}bread\u{00A0}")
        #expect(list.items[0].title == "bread")
        list.rename(id, "\u{000B}bread")
        #expect(list.items[0].title == "\u{000B}bread")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!
        let keptOriginal = TodoQuickAdd.parse("\u{200B} due 0784-06-02", now: now, calendar: calendar)
        #expect(keptOriginal.due == nil)
        #expect(keptOriginal.title.contains("\u{200B}"))
        #expect(TodoQuickAdd.parse("\u{200B}milk.", now: now, calendar: calendar).title == "\u{200B}milk")
        #expect(TodoQuickAdd.parse(" milk. ", now: now, calendar: calendar).title == "milk")
    }
}
