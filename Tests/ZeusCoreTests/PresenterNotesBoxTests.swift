import Foundation
import Testing
@testable import ZeusCore

@Suite("Presenter notes box")
struct PresenterNotesBoxTests {
    @Test func blankScalarsAreNamedAndLeaveAZeroWidthSpace() {
        #expect(PresenterNotesBox.blankScalars.contains(" "))
        #expect(PresenterNotesBox.blankScalars.contains("\t"))
        #expect(PresenterNotesBox.blankScalars.contains("\n"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{000B}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{000C}"))
        #expect(PresenterNotesBox.blankScalars.contains("\r"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{0085}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{00A0}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{1680}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{2000}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{200A}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{2028}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{2029}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{202F}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{205F}"))
        #expect(PresenterNotesBox.blankScalars.contains("\u{3000}"))
        #expect(!PresenterNotesBox.blankScalars.contains("\u{200B}"))
        #expect(PresenterNotesBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(PresenterNotesBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(PresenterNotesBox.trimmedText(" \t\n\u{00A0}\u{3000}") == "")
    }

    @Test func aTextOfOnlyNamedBlanksIsEmpty() {
        #expect(PresenterNotesBox.trimmedText("") == "")
        #expect(PresenterNotesBox.trimmedText(" \t\n\r") == "")
        #expect(PresenterNotesBox.trimmedText("\u{00A0}") == "")
        #expect(PresenterNotesBox.trimmedText("\u{1680}\u{2000}\u{2028}\u{202F}\u{205F}\u{3000}") == "")
        #expect(PresenterNotesBox.trimmedText("\u{200B}") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysInsideTheText() {
        #expect(PresenterNotesBox.trimmedText("\u{00A0}\u{200B}\u{00A0}") == "\u{200B}")
        #expect(PresenterNotesBox.trimmedText("\u{200B}Roadmap") == "\u{200B}Roadmap")
        #expect(PresenterNotesBox.trimmedText("Roadmap\u{200B}") == "Roadmap\u{200B}")
        #expect(PresenterNotesBox.trimmedText(" \nRoadmap\t") == "Roadmap")
    }

    @Test func aZeroWidthTitleAndNotesStayInTheScript() {
        let deck = PresenterDeck(app: .keynote, name: "\u{200B}", slides: [
            SlideNotes(number: 1, title: "\u{200B}", notes: "\u{200B}"),
        ])
        #expect(deck.script == "# 1 · \u{200B}\n\u{200B}")
        #expect(deck.hasNotes)
        #expect(deck.script(forSlide: 1) == "\u{200B}")
        #expect(deck.nextCue(after: 0) == "Next: \u{200B}")
        #expect(deck.isSameDocument("\u{200B}"))
        #expect(deck.isSameDocument(" \u{200B}.key"))
        #expect(deck.isSameDocument("Talk") == false)
    }

    @Test func namedBlanksLeaveTheCueAndARealTitleStays() {
        let blanks = PresenterDeck(app: .keynote, name: "Talk", slides: [
            SlideNotes(number: 1, title: "\u{00A0}", notes: " \t\n"),
        ])
        #expect(blanks.script == "# 1")
        #expect(!blanks.hasNotes)
        #expect(blanks.script(forSlide: 1) == "")
        #expect(blanks.nextCue(after: 0) == "Next: slide 1")
        #expect(blanks.isSameDocument(" \u{00A0}Talk.key\u{00A0}"))
        #expect(blanks.isSameDocument("\u{200B}") == false)

        let titled = PresenterDeck(app: .keynote, name: "Talk", slides: [
            SlideNotes(number: 1, title: " \nRoadmap\t", notes: " Hi "),
        ])
        #expect(titled.script == "# 1 · Roadmap\nHi")
        #expect(titled.hasNotes)
        #expect(titled.nextCue(after: 0) == "Next: Roadmap")
        #expect(titled.script(forSlide: 1) == "Hi")

        let marked = PresenterDeck(app: .keynote, name: "Talk", slides: [
            SlideNotes(number: 1, title: "\u{200B}", notes: "Hi"),
        ])
        #expect(marked.script == "# 1 · \u{200B}\nHi")
        #expect(marked.nextCue(after: 0) == "Next: \u{200B}")
    }
}
