import Foundation
import Testing
@testable import ZeusCore

/// The blank answer for a system-speech word. A zero-width space stays inside the word.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank, so these tests name the scalars.
@Suite("System speech marker alignment box")
struct SystemSpeechMarkerAlignmentBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.count == 25)
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{0009}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{000A}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{000B}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{000C}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{000D}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{0020}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{0085}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{00A0}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{1680}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2000}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2001}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2002}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2003}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2004}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2005}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2006}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2007}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2008}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2009}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{200A}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2028}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{2029}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{202F}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{205F}"))
        #expect(SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{3000}"))
        #expect(!SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{200B}"))
        #expect(!SystemSpeechMarkerAlignmentBox.blankScalars.contains("\u{200C}"))
    }

    @Test func aZeroWidthSpaceIsNotABlank() {
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{200B}") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{200C}") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("H") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("Hi") == false)
        let text = "show\u{200B}the"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [whole(text, time: 0.2)],
            duration: 1
        )
        #expect(marks == [ExplanationAlignmentMark(wordIndex: 0, start: 0.2, end: 1)])
    }

    @Test func aZeroWidthSpaceBesideABlankIsNotABlank() {
        #expect(SystemSpeechMarkerAlignmentBox.isBlank(" \u{200B}") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{200B} ") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\n\u{200B}\t") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{00A0}\u{200B}") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{3000}\u{200B}\u{2028}") == false)
        let text = "show\u{200B}the button"
        let first = "show\u{200B}the"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [whole(first, time: 0.2)],
            duration: 1
        )
        #expect(marks == [ExplanationAlignmentMark(wordIndex: 0, start: 0.2, end: 1)])
    }

    @Test func anEmptyTokenIsNotABlankAndNamedBlanksAreBlanks() {
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("") == false)
        #expect(SystemSpeechMarkerAlignmentBox.isBlank(" "))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\n"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\t"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\r"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{000B}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{000C}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{0085}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{00A0}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{1680}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{2000}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{200A}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{2028}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{2029}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{202F}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{205F}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{3000}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank(" \t\n\u{00A0}\u{3000}"))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank("\u{200B}") == false)
        let text = "where\u{00A0}is"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: text,
            markers: [whole(text, time: 0.2)],
            duration: 1
        )
        #expect(marks.isEmpty)
    }

    @Test func aTokenOfOnlyNamedBlanksIsABlank() {
        let blanks = SystemSpeechMarkerAlignmentBox.blankScalars.map { String($0) }
        #expect(blanks.count == 25)
        for token in blanks {
            #expect(SystemSpeechMarkerAlignmentBox.isBlank(token))
        }
        #expect(SystemSpeechMarkerAlignmentBox.isBlank(blanks.joined()))
        #expect(SystemSpeechMarkerAlignmentBox.isBlank(blanks.joined() + "\u{200B}") == false)
        let glued = "\u{200B}"
        let marks = SystemSpeechMarkerAlignment.wordMarks(
            text: glued,
            markers: [whole(glued, time: 0.1)],
            duration: 1
        )
        #expect(marks == [ExplanationAlignmentMark(wordIndex: 0, start: 0.1, end: 1)])
    }

    private func whole(_ text: String, time: Double) -> SystemSpeechMarkerFact {
        SystemSpeechMarkerFact(kind: .word, utf16Location: 0, utf16Length: text.utf16.count, time: time)
    }
}
