import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the name trim inside `ScribeSpeakerBook.setConfirmed`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Scribe confirmed name box")
struct ScribeConfirmedNameBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(ScribeConfirmedNameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(ScribeConfirmedNameBox.blankScalars.count == 5)
        #expect(ScribeConfirmedNameBox.blankScalars.contains(" "))
        #expect(ScribeConfirmedNameBox.blankScalars.contains("\t"))
        #expect(ScribeConfirmedNameBox.blankScalars.contains("\n"))
        #expect(ScribeConfirmedNameBox.blankScalars.contains("\r"))
        #expect(ScribeConfirmedNameBox.blankScalars.contains("\u{00A0}"))
        #expect(!ScribeConfirmedNameBox.blankScalars.contains("\u{200B}"))
        #expect(!ScribeConfirmedNameBox.blankScalars.contains("\u{000B}"))
        #expect(!ScribeConfirmedNameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedName() {
        #expect(ScribeConfirmedNameBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(ScribeConfirmedNameBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(ScribeConfirmedNameBox.trimmedName("\t\u{200B}\n") == "\u{200B}")
        #expect(ScribeConfirmedNameBox.trimmedName("\u{200B}Marie") == "\u{200B}Marie")
        #expect(ScribeConfirmedNameBox.trimmedName("Marie\u{200B}") == "Marie\u{200B}")
        #expect(ScribeConfirmedNameBox.trimmedName(" \t\n\r\u{00A0}") == "")
        #expect(ScribeConfirmedNameBox.trimmedName("") == "")
        #expect(ScribeConfirmedNameBox.trimmedName("\u{000B}Marie") == "\u{000B}Marie")
        #expect(ScribeConfirmedNameBox.trimmedName("\u{3000}Marie") == "\u{3000}Marie")
        #expect(ScribeConfirmedNameBox.trimmedName(" \tMarie\r\n") == "Marie")
        #expect(ScribeConfirmedNameBox.trimmedName("\u{00A0}Marie\u{00A0}") == "Marie")
        #expect(ScribeConfirmedNameBox.trimmedName("Marie") == "Marie")
        #expect(ScribeConfirmedNameBox.trimmedName("Ma\u{200B}rie") == "Ma\u{200B}rie")
        #expect(ScribeConfirmedNameBox.trimmedName("\n") == "")
        #expect(ScribeConfirmedNameBox.trimmedName("\r") == "")
        #expect(ScribeConfirmedNameBox.trimmedName("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnAConfirmedName() {
        func confirm(_ name: String) -> ScribeSpeakerBook {
            var book = ScribeSpeakerBook()
            book.setConfirmed(label: "Speaker 1", name: name)
            return book
        }

        let zero = confirm("\u{200B}")
        #expect(zero.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")
        #expect(zero.identity(forOriginal: "Speaker 1")?.source == .manual)
        #expect(zero.identity(forOriginal: "Speaker 1")?.confidence == 1)
        #expect(zero.identity(forOriginal: "Speaker 1")?.confirmed == true)
        #expect(zero.identity(forOriginal: "Speaker 1")?.originalLabel == "Speaker 1")

        let padded = confirm(" \u{200B} ")
        #expect(padded.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")

        let between = confirm("\n\u{200B}\r")
        #expect(between.identity(forOriginal: "Speaker 1")?.name == "\u{200B}")

        let leading = confirm("\u{200B}Marie")
        #expect(leading.identity(forOriginal: "Speaker 1")?.name == "\u{200B}Marie")

        let trailing = confirm("Marie\u{200B}")
        #expect(trailing.identity(forOriginal: "Speaker 1")?.name == "Marie\u{200B}")

        let inside = confirm("Ma\u{200B}rie")
        #expect(inside.identity(forOriginal: "Speaker 1")?.name == "Ma\u{200B}rie")

        let ideographic = confirm("\u{3000}")
        #expect(ideographic.identity(forOriginal: "Speaker 1")?.name == "\u{3000}")

        let ideographicName = confirm("\u{3000}Marie")
        #expect(ideographicName.identity(forOriginal: "Speaker 1")?.name == "\u{3000}Marie")

        let vertical = confirm("\u{000B}")
        #expect(vertical.identity(forOriginal: "Speaker 1")?.name == "\u{000B}")

        let verticalName = confirm("\u{000B}Marie")
        #expect(verticalName.identity(forOriginal: "Speaker 1")?.name == "\u{000B}Marie")

        let spaced = confirm(" \tMarie\r\n")
        #expect(spaced.identity(forOriginal: "Speaker 1")?.name == "Marie")
        #expect(spaced.identity(named: "Marie")?.name == "Marie")

        let noBreak = confirm("\u{00A0}Marie\u{00A0}")
        #expect(noBreak.identity(forOriginal: "Speaker 1")?.name == "Marie")

        for blank in ["", " ", "\t", "\n", "\r", "\u{00A0}", " \t\n\r\u{00A0}"] {
            let empty = confirm(blank)
            #expect(empty.identities.isEmpty)
        }
    }
}
