import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a learned shortcut match key. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Learned normalize box")
struct LearnedNormalizeBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedNormalizeBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedNormalizeBox.blankScalars.count == 5)
        #expect(LearnedNormalizeBox.blankScalars.contains(" "))
        #expect(LearnedNormalizeBox.blankScalars.contains("\t"))
        #expect(LearnedNormalizeBox.blankScalars.contains("\n"))
        #expect(LearnedNormalizeBox.blankScalars.contains("\r"))
        #expect(LearnedNormalizeBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedNormalizeBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedNormalizeBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedNormalizeBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedKey() {
        #expect(LearnedNormalizeBox.trimmedKey("\u{200B}") == "\u{200B}")
        #expect(LearnedNormalizeBox.trimmedKey(" \u{200B} ") == "\u{200B}")
        #expect(LearnedNormalizeBox.trimmedKey("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedNormalizeBox.trimmedKey("\u{200B}open") == "\u{200B}open")
        #expect(LearnedNormalizeBox.trimmedKey("open\u{200B}") == "open\u{200B}")
        #expect(LearnedNormalizeBox.trimmedKey(" \t\n\r\u{00A0}") == "")
        #expect(LearnedNormalizeBox.trimmedKey("") == "")
        #expect(LearnedNormalizeBox.trimmedKey("\u{000B}open") == "\u{000B}open")
        #expect(LearnedNormalizeBox.trimmedKey("\u{3000}open") == "\u{3000}open")
        #expect(LearnedNormalizeBox.trimmedKey(" \topen\r\n") == "open")
        #expect(LearnedNormalizeBox.trimmedKey("\u{00A0}open\u{00A0}") == "open")
        #expect(LearnedNormalizeBox.trimmedKey(" OPEN ") == "OPEN")
        #expect(LearnedNormalizeBox.trimmedKey("open") == "open")
    }

    @Test func aZeroWidthSpaceStaysOnTheMatchKey() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(matchedPhrase("\u{200B}open", stored: "Open", at: at) == nil)
        #expect(matchedPhrase("open\u{200B}", stored: "Open", at: at) == nil)
        #expect(matchedPhrase(" \u{200B}open ", stored: "Open", at: at) == nil)
        #expect(matchedPhrase("\u{200B}OPEN", stored: "Open", at: at) == nil)
        #expect(matchedPhrase("\u{3000}open", stored: "Open", at: at) == nil)
        #expect(matchedPhrase("\u{000B}open", stored: "Open", at: at) == nil)
        #expect(matchedPhrase("open", stored: "\u{200B}Open", at: at) == nil)
        #expect(matchedPhrase("\u{200B}open", stored: "\u{200B}Open", at: at) == "\u{200B}Open")
        #expect(matchedPhrase(" \u{200B}OPEN ", stored: "\u{200B}Open", at: at) == "\u{200B}Open")
        #expect(matchedPhrase(" OPEN ", stored: "Open", at: at) == "Open")
        #expect(matchedPhrase("\topen\r\n", stored: "Open", at: at) == "Open")
        #expect(matchedPhrase("\u{00A0}open\u{00A0}", stored: "Open", at: at) == "Open")
        #expect(matchedPhrase("open", stored: "Open", at: at) == "Open")
        var store = LearnedShortcutStore()
        guard case .saved(let shortcut) = store.save(phrase: " Open ", steps: [" click "], verified: true, at: at) else {
            Issue.record("save")
            return
        }
        #expect(shortcut.phrase == "Open")
        #expect(shortcut.steps == ["click"])
        #expect(store.match("open")?.phrase == "Open")
        #expect(store.match("\u{200B}open") == nil)
        #expect(store.save(phrase: "\u{200B}", steps: ["click"], verified: true, at: at) == .rejected("empty"))
        #expect(store.save(phrase: "open", steps: ["\u{200B}"], verified: true, at: at) == .rejected("empty"))
        #expect(store.save(phrase: "open", steps: ["click"], verified: false, at: at) == .rejected("unverified"))
    }
}

private func matchedPhrase(_ query: String, stored: String, at: Date) -> String? {
    let store = LearnedShortcutStore(book: LearnedBook(items: [
        LearnedShortcut(phrase: stored, steps: ["click"], savedAt: at),
    ]))
    return store.match(query)?.phrase
}
