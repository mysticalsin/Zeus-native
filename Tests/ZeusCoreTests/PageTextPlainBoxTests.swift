import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in plain page text. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Page text plain box")
struct PageTextPlainBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PageTextPlainBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PageTextPlainBox.blankScalars.count == 5)
        #expect(PageTextPlainBox.blankScalars.contains(" "))
        #expect(PageTextPlainBox.blankScalars.contains("\t"))
        #expect(PageTextPlainBox.blankScalars.contains("\n"))
        #expect(PageTextPlainBox.blankScalars.contains("\r"))
        #expect(PageTextPlainBox.blankScalars.contains("\u{00A0}"))
        #expect(!PageTextPlainBox.blankScalars.contains("\u{200B}"))
        #expect(!PageTextPlainBox.blankScalars.contains("\u{000B}"))
        #expect(!PageTextPlainBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedText() {
        #expect(PageTextPlainBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(PageTextPlainBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(PageTextPlainBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(PageTextPlainBox.trimmedText("\u{200B}Tokyo") == "\u{200B}Tokyo")
        #expect(PageTextPlainBox.trimmedText("Tokyo\u{200B}") == "Tokyo\u{200B}")
        #expect(PageTextPlainBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(PageTextPlainBox.trimmedText("") == "")
        #expect(PageTextPlainBox.trimmedText("\u{000B}Tokyo") == "\u{000B}Tokyo")
        #expect(PageTextPlainBox.trimmedText("\u{3000}Tokyo") == "\u{3000}Tokyo")
        #expect(PageTextPlainBox.trimmedText(" \tTokyo\r\n") == "Tokyo")
        #expect(PageTextPlainBox.trimmedText("\u{00A0}Tokyo\u{00A0}") == "Tokyo")
        #expect(PageTextPlainBox.trimmedText("A short trip.") == "A short trip.")
    }

    @Test func aZeroWidthSpaceStaysInPlainPageText() {
        #expect(PageTextPlainBox.trimmedText(" \u{200B}Tokyo ") == "\u{200B}Tokyo")
        #expect(PageText.plain("\u{200B}") == "\u{200B}")
        #expect(PageText.plain("\u{200B}Tokyo") == "\u{200B}Tokyo")
        #expect(PageText.plain("<b>\u{200B}Tokyo</b>") == "\u{200B}Tokyo")
        #expect(PageText.plain("<p>\u{200B}</p>") == "\u{200B}")
        #expect(PageText.plain(" \t\n\r\u{00A0}") == "")
        #expect(PageText.plain("<p> </p>") == "")
        #expect(PageText.plain("&nbsp;Tokyo&nbsp;") == "Tokyo")
        #expect(PageText.plain("  hello  ") == "hello")
        let html = "<html><script>alert(1)</script><body><h1>Tokyo</h1><p>A short trip.</p></body></html>"
        let plain = PageText.plain(html)
        #expect(plain.contains("Tokyo"))
        #expect(plain.contains("A short trip."))
        #expect(!plain.contains("alert"))
        #expect(!plain.contains("<"))
        let action = ZeusAction(kind: .browserSwitchTab, payload: ["title": .string("  Pricing  ")])
        #expect(BrowserCommand(action) == .switchTab(.title("Pricing")))
    }
}
