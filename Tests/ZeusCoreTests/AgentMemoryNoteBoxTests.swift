import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a remembered agent note. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Agent memory note box")
struct AgentMemoryNoteBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AgentMemoryNoteBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AgentMemoryNoteBox.blankScalars.count == 5)
        #expect(AgentMemoryNoteBox.blankScalars.contains(" "))
        #expect(AgentMemoryNoteBox.blankScalars.contains("\t"))
        #expect(AgentMemoryNoteBox.blankScalars.contains("\n"))
        #expect(AgentMemoryNoteBox.blankScalars.contains("\r"))
        #expect(AgentMemoryNoteBox.blankScalars.contains("\u{00A0}"))
        #expect(!AgentMemoryNoteBox.blankScalars.contains("\u{200B}"))
        #expect(!AgentMemoryNoteBox.blankScalars.contains("\u{000B}"))
        #expect(!AgentMemoryNoteBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedNote() {
        #expect(AgentMemoryNoteBox.trimmedNote("\u{200B}") == "\u{200B}")
        #expect(AgentMemoryNoteBox.trimmedNote(" \u{200B} ") == "\u{200B}")
        #expect(AgentMemoryNoteBox.trimmedNote("\t\u{200B}\n") == "\u{200B}")
        #expect(AgentMemoryNoteBox.trimmedNote("\u{200B}note") == "\u{200B}note")
        #expect(AgentMemoryNoteBox.trimmedNote("note\u{200B}") == "note\u{200B}")
        #expect(AgentMemoryNoteBox.trimmedNote(" \t\n\r\u{00A0}") == "")
        #expect(AgentMemoryNoteBox.trimmedNote("") == "")
        #expect(AgentMemoryNoteBox.trimmedNote("\u{000B}note") == "\u{000B}note")
        #expect(AgentMemoryNoteBox.trimmedNote("\u{3000}note") == "\u{3000}note")
        #expect(AgentMemoryNoteBox.trimmedNote(" \tnote\r\n") == "note")
        #expect(AgentMemoryNoteBox.trimmedNote("\u{00A0}note\u{00A0}") == "note")
        #expect(AgentMemoryNoteBox.trimmedNote("note") == "note")
        #expect(AgentMemoryNoteBox.trimmedNote("a\u{200B}b") == "a\u{200B}b")
        #expect(AgentMemoryNoteBox.trimmedNote("\nnote") == "note")
        #expect(AgentMemoryNoteBox.trimmedNote("\rnote") == "note")
    }

    @Test func aZeroWidthSpaceStaysOnARememberedNote() {
        var empty = AgentMemory()
        empty.remember("\u{200B}")
        #expect(empty.notes.map(\.text) == ["\u{200B}"])

        var wrapped = AgentMemory()
        wrapped.remember(" \u{200B} ")
        #expect(wrapped.notes.map(\.text) == ["\u{200B}"])

        var vertical = AgentMemory()
        vertical.remember("\u{000B}note")
        #expect(vertical.notes.map(\.text) == ["\u{000B}note"])

        var ideographic = AgentMemory()
        ideographic.remember("\u{3000}note")
        #expect(ideographic.notes.map(\.text) == ["\u{3000}note"])

        var blanks = AgentMemory()
        blanks.remember(" \t\n\r\u{00A0}")
        #expect(blanks.notes.isEmpty)

        var nbsp = AgentMemory()
        nbsp.remember("\u{00A0}note\u{00A0}")
        #expect(nbsp.notes.map(\.text) == ["note"])

        var spaced = AgentMemory()
        spaced.remember(" \tnote\r\n")
        #expect(spaced.notes.map(\.text) == ["note"])

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var pinned = AgentMemory()
        pinned.remember("  note  ", pinned: true, at: date)
        #expect(pinned.notes.count == 1)
        #expect(pinned.notes[0].text == "note")
        #expect(pinned.notes[0].pinned)
        #expect(pinned.notes[0].date == date)

        var interior = AgentMemory()
        interior.remember("a\u{200B}b")
        #expect(interior.notes.map(\.text) == ["a\u{200B}b"])

        let long = String(repeating: "a", count: 401)
        var capped = AgentMemory()
        capped.remember(" \(long) ")
        #expect(capped.notes.map(\.text) == [String(repeating: "a", count: 400)])

        let agents = AgentProfile.builtIn
        #expect(AgentRouter.route(" \u{200B}ask Scout to look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \u{200B}look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout to \u{000B}look", agents: agents)?.request == "\u{000B}look")
        #expect(AgentRouter.route("\u{000B}ask Scout to look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("\u{3000}ask Scout to look", agents: agents)?.request == "look")
        #expect(AgentRouter.route("ask Scout\u{200B} to look", agents: agents) == nil)
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.agent.name == "Scout")
        #expect(AgentRouter.route("  ask Scout to look  ", agents: agents)?.request == "look")
    }
}
