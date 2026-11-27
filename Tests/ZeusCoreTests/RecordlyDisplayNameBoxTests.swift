import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a Recordly display name. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Recordly display name box")
struct RecordlyDisplayNameBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(RecordlyDisplayNameBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(RecordlyDisplayNameBox.blankScalars.count == 5)
        #expect(RecordlyDisplayNameBox.blankScalars.contains(" "))
        #expect(RecordlyDisplayNameBox.blankScalars.contains("\t"))
        #expect(RecordlyDisplayNameBox.blankScalars.contains("\n"))
        #expect(RecordlyDisplayNameBox.blankScalars.contains("\r"))
        #expect(RecordlyDisplayNameBox.blankScalars.contains("\u{00A0}"))
        #expect(!RecordlyDisplayNameBox.blankScalars.contains("\u{200B}"))
        #expect(!RecordlyDisplayNameBox.blankScalars.contains("\u{000B}"))
        #expect(!RecordlyDisplayNameBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedName() {
        #expect(RecordlyDisplayNameBox.trimmedName("\u{200B}") == "\u{200B}")
        #expect(RecordlyDisplayNameBox.trimmedName(" \u{200B} ") == "\u{200B}")
        #expect(RecordlyDisplayNameBox.trimmedName("\t\u{200B}\n") == "\u{200B}")
        #expect(RecordlyDisplayNameBox.trimmedName("\u{200B}Built-in Retina Display") == "\u{200B}Built-in Retina Display")
        #expect(RecordlyDisplayNameBox.trimmedName("Built-in Retina Display\u{200B}") == "Built-in Retina Display\u{200B}")
        #expect(RecordlyDisplayNameBox.trimmedName(" \t\n\r\u{00A0}") == "")
        #expect(RecordlyDisplayNameBox.trimmedName("") == "")
        #expect(RecordlyDisplayNameBox.trimmedName("\u{000B}Built-in Retina Display") == "\u{000B}Built-in Retina Display")
        #expect(RecordlyDisplayNameBox.trimmedName("\u{3000}Built-in Retina Display") == "\u{3000}Built-in Retina Display")
        #expect(RecordlyDisplayNameBox.trimmedName(" \tBuilt-in Retina Display\r\n") == "Built-in Retina Display")
        #expect(RecordlyDisplayNameBox.trimmedName("\u{00A0}Built-in Retina Display\u{00A0}") == "Built-in Retina Display")
        #expect(RecordlyDisplayNameBox.trimmedName("Built-in\u{00A0}Retina") == "Built-in\u{00A0}Retina")
    }

    @Test func aZeroWidthSpaceStaysInTheDisplayTitle() {
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{200B}", position: 0) == "\u{200B}")
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{200B}", position: 0) != "Display 1")
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{200B}Built-in Retina Display", position: 0) == "\u{200B}Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "Built-in Retina Display\u{200B}", position: 0) == "Built-in Retina Display\u{200B}")
        #expect(RecordlyDisplayChoiceBox.title(name: " \u{200B}Built-in Retina Display ", position: 0) == "\u{200B}Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "  Built-in Retina Display  ", position: 0) == "Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "\nBuilt-in Retina Display\t", position: 0) == "Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{00A0}Built-in Retina Display\u{00A0}", position: 0) == "Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{000B}Built-in Retina Display", position: 0) == "\u{000B}Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "\u{3000}Built-in Retina Display", position: 0) == "\u{3000}Built-in Retina Display")
        #expect(RecordlyDisplayChoiceBox.title(name: "   ", position: 1) == "Display 2")
        #expect(RecordlyDisplayChoiceBox.title(name: " \t\n\r\u{00A0}", position: 0) == "Display 1")
        #expect(RecordlyDisplayChoiceBox.title(name: nil, position: 0) == "Display 1")
        #expect(RecordlyDisplayChoiceBox.title(name: "", position: 0) == "Display 1")
        #expect(RecordlyDisplayChoiceBox.compactLine(name: "\u{200B}", position: 0, isMain: false) == "\u{200B}")
        #expect(RecordlyDisplayChoiceBox.compactLine(name: "  ", position: 1, isMain: false) == "Display 2")
        #expect(RecordlyDisplayChoiceBox.spokenLabel(name: "\u{200B}Built-in Retina Display", position: 0, width: 1512, height: 982, isMain: true)
            == "\u{200B}Built-in Retina Display, 1512 \u{00D7} 982, main display")
        #expect(RecordlyDisplayChoiceBox.spokenLabel(name: "\u{00A0}Built-in Retina Display\u{00A0}", position: 0, width: 1512, height: 982, isMain: false)
            == "Built-in Retina Display, 1512 \u{00D7} 982")
    }
}
