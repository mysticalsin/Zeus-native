import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a browser tab title. These tests name the blanks.
/// Linux `CharacterSet.whitespaces` treats U+200B as blank.
@Suite("Tab match title box")
struct TabMatchBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(TabMatchBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(TabMatchBox.blankScalars.count == 5)
        #expect(TabMatchBox.blankScalars.contains(" "))
        #expect(TabMatchBox.blankScalars.contains("\t"))
        #expect(TabMatchBox.blankScalars.contains("\n"))
        #expect(TabMatchBox.blankScalars.contains("\r"))
        #expect(TabMatchBox.blankScalars.contains("\u{00A0}"))
        #expect(!TabMatchBox.blankScalars.contains("\u{200B}"))
        #expect(!TabMatchBox.blankScalars.contains("\u{000B}"))
        #expect(!TabMatchBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedTitle() {
        #expect(TabMatchBox.trimmedTitle("\u{200B}") == "\u{200B}")
        #expect(TabMatchBox.trimmedTitle(" \u{200B} ") == "\u{200B}")
        #expect(TabMatchBox.trimmedTitle("\t\u{200B}\n") == "\u{200B}")
        #expect(TabMatchBox.trimmedTitle("\u{200B}Tokyo") == "\u{200B}Tokyo")
        #expect(TabMatchBox.trimmedTitle("Tokyo\u{200B}") == "Tokyo\u{200B}")
        #expect(TabMatchBox.trimmedTitle(" \t\n\r\u{00A0}") == "")
        #expect(TabMatchBox.trimmedTitle("") == "")
        #expect(TabMatchBox.trimmedTitle("\u{000B}Tokyo") == "\u{000B}Tokyo")
        #expect(TabMatchBox.trimmedTitle("\u{3000}Tokyo") == "\u{3000}Tokyo")
        #expect(TabMatchBox.trimmedTitle(" \tTokyo\r\n") == "Tokyo")
        #expect(TabMatchBox.trimmedTitle("\u{00A0}Tokyo\u{00A0}") == "Tokyo")
        #expect(TabMatchBox.trimmedTitle("Pricing") == "Pricing")
    }

    @Test func aZeroWidthSpaceStaysInTheTabMatch() {
        #expect(TabMatchBox.trimmedTitle(" \u{200B}Tokyo ") == "\u{200B}Tokyo")
        #expect(BrowserCommand.tabMatch(["title": .string("\u{200B}")]) == .title("\u{200B}"))
        #expect(BrowserCommand.tabMatch(["title": .string(" \u{200B}Tokyo ")]) == .title("\u{200B}Tokyo"))
        #expect(BrowserCommand.tabMatch(["title": .string("  Pricing  ")]) == .title("Pricing"))
        #expect(BrowserCommand.tabMatch(["title": .string(" \t\n\r\u{00A0}")]) == nil)
        #expect(BrowserCommand.tabMatch(["title": .string("\u{00A0}Tokyo\u{00A0}")]) == .title("Tokyo"))
        #expect(BrowserCommand.tabMatch(["title": .string("\u{3000}Tokyo")]) == .title("\u{3000}Tokyo"))
        #expect(BrowserCommand.tabMatch(["title": .string("\u{000B}Tokyo")]) == .title("\u{000B}Tokyo"))
        #expect(BrowserCommand.tabMatch(["tabId": .number(381), "title": .string(" \u{200B}")]) == .id(381))
        let kept = ZeusAction(kind: .browserSwitchTab, payload: ["title": .string("\u{200B}")])
        #expect(BrowserCommand(kept) == .switchTab(.title("\u{200B}")))
        let priced = ZeusAction(kind: .browserSwitchTab, payload: ["title": .string("  Pricing  ")])
        #expect(BrowserCommand(priced) == .switchTab(.title("Pricing")))
        let blanks = ZeusAction(kind: .browserCloseTab, payload: ["title": .string(" \t\n\r\u{00A0}")])
        #expect(BrowserCommand(blanks) == nil)
        let closed = ZeusAction(kind: .browserCloseTab, payload: ["title": .string("\u{200B}")])
        #expect(BrowserCommand(closed) == .closeTab(.title("\u{200B}")))
    }
}
