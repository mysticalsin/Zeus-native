import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a Beamer tray-menu title. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Beamer menu title box")
struct BeamerMenuTitleBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BeamerMenuTitleBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BeamerMenuTitleBox.blankScalars.count == 5)
        #expect(BeamerMenuTitleBox.blankScalars.contains(" "))
        #expect(BeamerMenuTitleBox.blankScalars.contains("\t"))
        #expect(BeamerMenuTitleBox.blankScalars.contains("\n"))
        #expect(BeamerMenuTitleBox.blankScalars.contains("\r"))
        #expect(BeamerMenuTitleBox.blankScalars.contains("\u{00A0}"))
        #expect(!BeamerMenuTitleBox.blankScalars.contains("\u{200B}"))
        #expect(!BeamerMenuTitleBox.blankScalars.contains("\u{000B}"))
        #expect(!BeamerMenuTitleBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedTitle() {
        #expect(BeamerMenuTitleBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(BeamerMenuTitleBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(BeamerMenuTitleBox.trimmedTitle("\t\u{200B}\n") == "\u{200B}")
        #expect(BeamerMenuTitleBox.trimmedTitle("\u{200B}Driving") == "\u{200B}Driving")
        #expect(BeamerMenuTitleBox.trimmedTitle("Driving\u{200B}") == "Driving\u{200B}")
        #expect(BeamerMenuTitleBox.trimmedTitle(" \t\n\r\u{00A0}") == "")
        #expect(BeamerMenuTitleBox.trimmedTitle("") == "")
        #expect(BeamerMenuTitleBox.trimmedTitle("\u{000B}Driving") == "\u{000B}Driving")
        #expect(BeamerMenuTitleBox.trimmedTitle("\u{3000}Driving") == "\u{3000}Driving")
        #expect(BeamerMenuTitleBox.trimmedTitle(" \tDriving\r\n") == "Driving")
        #expect(BeamerMenuTitleBox.trimmedTitle("\u{00A0}Driving\u{00A0}") == "Driving")
        #expect(BeamerMenuTitleBox.trimmedTitle("Driving") == "Driving")
    }

    @Test func aZeroWidthSpaceStaysOnTheParsedTitle() {
        #expect(BeamerMenuState.parse(titles: ["\u{200B}Driving Office"]).link == .idle)
        #expect(BeamerMenuState.parse(titles: ["\u{200B}Beamer 1.5.18"]).version == nil)
        #expect(BeamerMenuState.parse(titles: ["\u{200B}Send input to Studio"]).targets == [])
        #expect(BeamerMenuState.parse(titles: ["\u{200B}Send input to Studio"]).canSend == false)
        #expect(BeamerMenuState.parse(titles: ["\u{200B}"]).link == .idle)
        #expect(BeamerMenuState.parse(titles: [" \t\n\r\u{00A0}"]).link == .idle)
        #expect(BeamerMenuState.parse(titles: ["\u{000B}Driving Office"]).link == .idle)
        #expect(BeamerMenuState.parse(titles: ["\u{3000}Driving Office"]).link == .idle)
        #expect(BeamerMenuState.parse(titles: ["  Driving Office  "]).link == .driving("Office"))
        #expect(BeamerMenuState.parse(titles: ["\tDriving Office\n"]).link == .driving("Office"))
        #expect(BeamerMenuState.parse(titles: ["\u{00A0}Driving Office\u{00A0}"]).link == .driving("Office"))
        #expect(BeamerMenuState.parse(titles: ["\nDriving Office\r"]).link == .driving("Office"))
        #expect(BeamerMenuState.parse(titles: ["Driving Office"]).link == .driving("Office"))
        let state = BeamerMenuState.parse(titles: ["Beamer 1.5.18", "Driving Studio PC", "Pause crossing"])
        #expect(state.version == "1.5.18")
        #expect(state.link == .driving("Studio PC"))
        #expect(state.paused == false)
        #expect(BeamerMenuState.parse(titles: ["missing value", ""]).paused == nil)
        #expect(BeamerMenuState.parse(titles: ["\u{00A0}missing value\u{00A0}"]).paused == nil)
        #expect(BeamerMenuState.parse(titles: ["  Send input to Studio PC  "]).targets == ["Studio PC"])
    }
}
