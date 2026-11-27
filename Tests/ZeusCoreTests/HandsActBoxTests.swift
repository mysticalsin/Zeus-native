import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a hands control label. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Hands act box")
struct HandsActBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(HandsActBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(HandsActBox.blankScalars.count == 5)
        #expect(HandsActBox.blankScalars.contains(" "))
        #expect(HandsActBox.blankScalars.contains("\t"))
        #expect(HandsActBox.blankScalars.contains("\n"))
        #expect(HandsActBox.blankScalars.contains("\r"))
        #expect(HandsActBox.blankScalars.contains("\u{00A0}"))
        #expect(!HandsActBox.blankScalars.contains("\u{200B}"))
        #expect(!HandsActBox.blankScalars.contains("\u{000B}"))
        #expect(!HandsActBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInALabel() {
        #expect(HandsActBox.trimmedLabel("\u{200B}") == "\u{200B}")
        #expect(HandsActBox.trimmedLabel(" \u{200B} ") == "\u{200B}")
        #expect(HandsActBox.trimmedLabel("\t\u{200B}\n") == "\u{200B}")
        #expect(HandsActBox.trimmedLabel("\u{200B}Save") == "\u{200B}Save")
        #expect(HandsActBox.trimmedLabel("Save\u{200B}") == "Save\u{200B}")
        #expect(HandsActBox.trimmedLabel(" \t\n\r\u{00A0}") == "")
        #expect(HandsActBox.trimmedLabel("\u{000B}Save") == "\u{000B}Save")
        #expect(HandsActBox.trimmedLabel("\u{3000}Save") == "\u{3000}Save")
    }

    @Test func aZeroWidthSpaceDoesNotSelectAnotherControl() {
        let world = HandsWorld.fixture()
        #expect(world.element("\u{200B}Save") == nil)
        #expect(world.element(" \u{200B} ") == nil)
        #expect(world.element("\u{200B}") == nil)
        #expect(world.element(" \t\n\r\u{00A0}Save\u{00A0} ")?.id == "save")
        #expect(world.element("\u{00A0}Search\u{00A0}")?.id == "search")
        #expect(world.element("\u{000B}Save") == nil)
        #expect(world.element("\u{3000}Save") == nil)
        #expect(world.element("Save")?.id == "save")
        var clicking = HandsWorld.fixture()
        let missed = clicking.perform(.click("\u{200B}Save", kind: "click"))
        #expect(!missed.ok)
        #expect(missed.changed == "failed")
        let hit = clicking.perform(.click("\u{00A0}Save\u{00A0}", kind: "click"))
        #expect(hit.ok)
        #expect(clicking.element("Save")?.pressed == true)
    }
}
