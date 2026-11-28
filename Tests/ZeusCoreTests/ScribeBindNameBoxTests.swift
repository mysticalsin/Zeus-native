import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the name trim inside `ScribeSpeakerBook.bindAutomatic`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe bind name box")
struct ScribeBindNameBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeBindNameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeBindNameBox.blankScalars.count == 5)
        #expect(ScribeBindNameBox.blankScalars.contains(" "))
        #expect(ScribeBindNameBox.blankScalars.contains("\t"))
        #expect(ScribeBindNameBox.blankScalars.contains("\n"))
        #expect(ScribeBindNameBox.blankScalars.contains("\r"))
        #expect(ScribeBindNameBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeBindNameBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeBindNameBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeBindNameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedName() {
        #expect(ScribeBindNameBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(ScribeBindNameBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(ScribeBindNameBox.trimmedName("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeBindNameBox.trimmedName("\u{200B}Marie") == "\u{200B}Marie")
        #expect(ScribeBindNameBox.trimmedName("Marie\u{200B}") == "Marie\u{200B}")
        #expect(ScribeBindNameBox.trimmedName(" \t\n\r\u{00A0}") == "")
        #expect(ScribeBindNameBox.trimmedName("") == "")
        #expect(ScribeBindNameBox.trimmedName("\u{000B}Marie") == "\u{000B}Marie")
        #expect(ScribeBindNameBox.trimmedName("\u{3000}Marie") == "\u{3000}Marie")
        #expect(ScribeBindNameBox.trimmedName(" \tMarie\r\n") == "Marie")
        #expect(ScribeBindNameBox.trimmedName("\u{00A0}Marie\u{00A0}") == "Marie")
        #expect(ScribeBindNameBox.trimmedName("Marie") == "Marie")
        #expect(ScribeBindNameBox.trimmedName("Ma\u{200B}rie") == "Ma\u{200B}rie")
        #expect(ScribeBindNameBox.trimmedName("\n") == "")
        #expect(ScribeBindNameBox.trimmedName("\r") == "")
        #expect(ScribeBindNameBox.trimmedName("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnAnAutomaticName() {
        func bind(_ name: String) -> (ScribeSpeakerBook.BindResult, ScribeSpeakerBook) {
            var book = ScribeSpeakerBook()
            let result = book.bindAutomatic(label: "Speaker 1", name: name, source: .callWindow, confidence: 0.9)
            return (result, book)
        }

        let zero = bind("\u{200B}")
        #expect(zero.0 == .bound)
        #expect(zero.1.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")
        #expect(zero.1.identity(forOriginal: "Speaker 1")?.source == .callWindow)
        #expect(zero.1.identity(forOriginal: "Speaker 1")?.confidence == 0.9)
        #expect(zero.1.identity(forOriginal: "Speaker 1")?.confirmed == false)
        #expect(zero.1.identity(forOriginal: "Speaker 1")?.originalLabel == "Speaker 1")

        let padded = bind(" \u{200B} ")
        #expect(padded.0 == .bound)
        #expect(padded.1.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")

        let between = bind("\n\u{200B}\r")
        #expect(between.0 == .bound)
        #expect(between.1.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")

        let leading = bind("\u{200B}Marie")
        #expect(leading.0 == .bound)
        #expect(leading.1.identity(forOriginal: "Speaker 1")?.name == "\u{200B}Marie")

        let trailing = bind("Marie\u{200B}")
        #expect(trailing.0 == .bound)
        #expect(trailing.1.identity(forOriginal: "Speaker 1")?.name == "Marie\u{200B}")

        let inside = bind("Ma\u{200B}rie")
        #expect(inside.0 == .bound)
        #expect(inside.1.identity(forOriginal: "Speaker 1")?.name == "Ma\u{200B}rie")

        let ideographic = bind("\u{3000}")
        #expect(ideographic.0 == .bound)
        #expect(ideographic.1.identity(forOriginal: "Speaker 1")?.name == "\u{3000}")

        let ideographicName = bind("\u{3000}Marie")
        #expect(ideographicName.0 == .bound)
        #expect(ideographicName.1.identity(forOriginal: "Speaker 1")?.name == "\u{3000}Marie")

        let vertical = bind("\u{000B}")
        #expect(vertical.0 == .bound)
        #expect(vertical.1.identity(forOriginal: "Speaker 1")?.name == "\u{000B}")

        let verticalName = bind("\u{000B}Marie")
        #expect(verticalName.0 == .bound)
        #expect(verticalName.1.identity(forOriginal: "Speaker 1")?.name == "\u{000B}Marie")

        let spaced = bind(" \tMarie\r\n")
        #expect(spaced.0 == .bound)
        #expect(spaced.1.identity(forOriginal: "Speaker 1")?.name == "Marie")
        #expect(spaced.1.identity(named: "Marie")?.name == "Marie")

        let noBreak = bind("\u{00A0}Marie\u{00A0}")
        #expect(noBreak.0 == .bound)
        #expect(noBreak.1.identity(forOriginal: "Speaker 1")?.name == "Marie")

        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}"] {
            let empty = bind(blank)
            #expect(empty.0 == .unchanged)
            #expect(empty.1.identities.isEmpty)
        }
    }
}
