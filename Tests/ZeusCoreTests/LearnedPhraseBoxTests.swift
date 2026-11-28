import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a learned shortcut phrase. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Learned phrase box")
struct LearnedPhraseBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedPhraseBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedPhraseBox.blankScalars.count == 5)
        #expect(LearnedPhraseBox.blankScalars.contains(" "))
        #expect(LearnedPhraseBox.blankScalars.contains("\t"))
        #expect(LearnedPhraseBox.blankScalars.contains("\n"))
        #expect(LearnedPhraseBox.blankScalars.contains("\r"))
        #expect(LearnedPhraseBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedPhraseBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedPhraseBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedPhraseBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedPhrase() {
        #expect(LearnedPhraseBox.trimmedPhrase("\u{200B}") == "\u{200B}")
        #expect(LearnedPhraseBox.trimmedPhrase(" \u{200B} ") == "\u{200B}")
        #expect(LearnedPhraseBox.trimmedPhrase("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedPhraseBox.trimmedPhrase("\u{200B}open") == "\u{200B}open")
        #expect(LearnedPhraseBox.trimmedPhrase("open\u{200B}") == "open\u{200B}")
        #expect(LearnedPhraseBox.trimmedPhrase(" \t\n\r\u{00A0}") == "")
        #expect(LearnedPhraseBox.trimmedPhrase("") == "")
        #expect(LearnedPhraseBox.trimmedPhrase("\u{000B}open") == "\u{000B}open")
        #expect(LearnedPhraseBox.trimmedPhrase("\u{3000}open") == "\u{3000}open")
        #expect(LearnedPhraseBox.trimmedPhrase(" \topen\r\n") == "open")
        #expect(LearnedPhraseBox.trimmedPhrase("\u{00A0}open\u{00A0}") == "open")
        #expect(LearnedPhraseBox.trimmedPhrase("open") == "open")
    }

    @Test func aZeroWidthSpaceStaysOnTheSavedPhrase() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(phrase("\u{200B}", at: at) == "\u{200B}")
        #expect(phrase(" \u{200B} ", at: at) == "\u{200B}")
        #expect(phrase("\t\u{200B}\n", at: at) == "\u{200B}")
        #expect(phrase("\u{200B}open", at: at) == "\u{200B}open")
        #expect(phrase("open\u{200B}", at: at) == "open\u{200B}")
        #expect(phrase("\u{3000}open", at: at) == "\u{3000}open")
        #expect(phrase("\u{000B}open", at: at) == "\u{000B}open")
        #expect(phrase(" \t\n\r\u{00A0}", at: at) == nil)
        #expect(phrase("", at: at) == nil)
        #expect(phrase(" \topen\r\n", at: at) == "open")
        #expect(phrase("\u{00A0}open\u{00A0}", at: at) == "open")
        #expect(phrase("open", at: at) == "open")
        #expect(phrase("open", steps: [" click "], at: at) == "open")
        #expect(steps("open", [" click "], at: at) == ["click"])
        var store = LearnedShortcutStore()
        #expect(store.save(phrase: "open", steps: ["click"], verified: false, at: at) == .rejected("unverified"))
    }
}

private func phrase(_ raw: String, steps: [String] = ["click"], at: Date) -> String? {
    var store = LearnedShortcutStore()
    guard case .saved(let shortcut) = store.save(phrase: raw, steps: steps, verified: true, at: at) else { return nil }
    return shortcut.phrase
}

private func steps(_ raw: String, _ rawSteps: [String], at: Date) -> [String]? {
    var store = LearnedShortcutStore()
    guard case .saved(let shortcut) = store.save(phrase: raw, steps: rawSteps, verified: true, at: at) else { return nil }
    return shortcut.steps
}
