import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the partial trim inside `LiveWordsHUD.applyPartial`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Live words partial box")
struct LiveWordsPartialBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LiveWordsPartialBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LiveWordsPartialBox.blankScalars.count == 5)
        #expect(LiveWordsPartialBox.blankScalars.contains(" "))
        #expect(LiveWordsPartialBox.blankScalars.contains("\t"))
        #expect(LiveWordsPartialBox.blankScalars.contains("\n"))
        #expect(LiveWordsPartialBox.blankScalars.contains("\r"))
        #expect(LiveWordsPartialBox.blankScalars.contains("\u{00A0}"))
        #expect(!LiveWordsPartialBox.blankScalars.contains("\u{200B}"))
        #expect(!LiveWordsPartialBox.blankScalars.contains("\u{000B}"))
        #expect(!LiveWordsPartialBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPartial() {
        #expect(LiveWordsPartialBox.trimmedPartial("\u{200B}") == "\u{200B}")
        #expect(LiveWordsPartialBox.trimmedPartial(" \u{200B} ") == "\u{200B}")
        #expect(LiveWordsPartialBox.trimmedPartial("\t\u{200B}\n") == "\u{200B}")
        #expect(LiveWordsPartialBox.trimmedPartial("\u{200B}open") == "\u{200B}open")
        #expect(LiveWordsPartialBox.trimmedPartial("open\u{200B}") == "open\u{200B}")
        #expect(LiveWordsPartialBox.trimmedPartial(" \t\n\r\u{00A0}") == "")
        #expect(LiveWordsPartialBox.trimmedPartial("") == "")
        #expect(LiveWordsPartialBox.trimmedPartial("\u{000B}open") == "\u{000B}open")
        #expect(LiveWordsPartialBox.trimmedPartial("\u{3000}open") == "\u{3000}open")
        #expect(LiveWordsPartialBox.trimmedPartial(" \topen\r\n") == "open")
        #expect(LiveWordsPartialBox.trimmedPartial("\u{00A0}open\u{00A0}") == "open")
        #expect(LiveWordsPartialBox.trimmedPartial("open") == "open")
        #expect(LiveWordsPartialBox.trimmedPartial("op\u{200B}en") == "op\u{200B}en")
        #expect(LiveWordsPartialBox.trimmedPartial("\n") == "")
        #expect(LiveWordsPartialBox.trimmedPartial("\r") == "")
        #expect(LiveWordsPartialBox.trimmedPartial("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheLivePartial() {
        #expect(visible("\u{200B}") == "\u{200B}")
        #expect(updates("\u{200B}") == 1)
        #expect(visible(" \u{200B} ") == "\u{200B}")
        #expect(visible("\t\u{200B}\n") == "\u{200B}")
        #expect(visible("\u{200B}open") == "\u{200B}open")
        #expect(visible("\u{200B}open") != "open")
        #expect(visible("open\u{200B}") == "open\u{200B}")
        #expect(visible("open\u{200B}") != "open")
        #expect(visible("op\u{200B}en") == "op\u{200B}en")
        #expect(visible("op\u{200B}en") != "open")
        #expect(visible("\u{200B}") != "")
        #expect(visible("   ") == "")
        #expect(updates("   ") == 0)
        #expect(visible(" \t\n\r\u{00A0}") == "")
        #expect(updates(" \t\n\r\u{00A0}") == 0)
        #expect(visible("\u{00A0}open\u{00A0}") == "open")
        #expect(visible(" \topen\r\n") == "open")
        #expect(visible("\u{3000}open") == "\u{3000}open")
        #expect(visible("\u{3000}open") != "open")
        #expect(visible("\u{000B}open") == "\u{000B}open")
        #expect(visible("\u{000B}open") != "open")
        #expect(visible("open") == "open")
        #expect(visible("\n") == "")
        #expect(visible("\r") == "")
        #expect(visible("\n\u{200B}\r") == "\u{200B}")
        #expect(visible("\n\u{200B}\r") != "")
        var hud = LiveWordsHUD()
        hud.applyPartial("open")
        hud.applyPartial("open")
        #expect(hud.updates == 1)
        hud.applyPartial(" \u{200B} ")
        #expect(hud.visible == "\u{200B}")
        #expect(hud.updates == 2)
        hud.clear()
        #expect(hud.visible == "")
        #expect(hud.updates == 2)
    }

    private func visible(_ text: String) -> String {
        var hud = LiveWordsHUD()
        hud.applyPartial(text)
        return hud.visible
    }

    private func updates(_ text: String) -> Int {
        var hud = LiveWordsHUD()
        hud.applyPartial(text)
        return hud.updates
    }
}
