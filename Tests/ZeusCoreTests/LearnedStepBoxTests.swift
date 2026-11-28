import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on a learned shortcut step. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Learned step box")
struct LearnedStepBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(LearnedStepBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(LearnedStepBox.blankScalars.count == 5)
        #expect(LearnedStepBox.blankScalars.contains(" "))
        #expect(LearnedStepBox.blankScalars.contains("\t"))
        #expect(LearnedStepBox.blankScalars.contains("\n"))
        #expect(LearnedStepBox.blankScalars.contains("\r"))
        #expect(LearnedStepBox.blankScalars.contains("\u{00A0}"))
        #expect(!LearnedStepBox.blankScalars.contains("\u{200B}"))
        #expect(!LearnedStepBox.blankScalars.contains("\u{000B}"))
        #expect(!LearnedStepBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedStep() {
        #expect(LearnedStepBox.trimmedStep("\u{200B}") == "\u{200B}")
        #expect(LearnedStepBox.trimmedStep(" \u{200B} ") == "\u{200B}")
        #expect(LearnedStepBox.trimmedStep("\t\u{200B}\n") == "\u{200B}")
        #expect(LearnedStepBox.trimmedStep("\u{200B}click") == "\u{200B}click")
        #expect(LearnedStepBox.trimmedStep("click\u{200B}") == "click\u{200B}")
        #expect(LearnedStepBox.trimmedStep(" \t\n\r\u{00A0}") == "")
        #expect(LearnedStepBox.trimmedStep("") == "")
        #expect(LearnedStepBox.trimmedStep("\u{000B}click") == "\u{000B}click")
        #expect(LearnedStepBox.trimmedStep("\u{3000}click") == "\u{3000}click")
        #expect(LearnedStepBox.trimmedStep(" \tclick\r\n") == "click")
        #expect(LearnedStepBox.trimmedStep("\u{00A0}click\u{00A0}") == "click")
        #expect(LearnedStepBox.trimmedStep("click") == "click")
    }

    @Test func aZeroWidthSpaceStaysOnTheSavedStep() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(savedSteps(["\u{200B}"], at: at) == ["\u{200B}"])
        #expect(savedSteps([" \u{200B} "], at: at) == ["\u{200B}"])
        #expect(savedSteps(["\t\u{200B}\n"], at: at) == ["\u{200B}"])
        #expect(savedSteps(["\u{200B}click"], at: at) == ["\u{200B}click"])
        #expect(savedSteps(["click\u{200B}"], at: at) == ["click\u{200B}"])
        #expect(savedSteps(["\u{3000}click"], at: at) == ["\u{3000}click"])
        #expect(savedSteps(["\u{000B}click"], at: at) == ["\u{000B}click"])
        #expect(savedSteps([" \t\n\r\u{00A0}"], at: at) == nil)
        #expect(savedSteps([""], at: at) == nil)
        #expect(savedSteps([" \tclick\r\n"], at: at) == ["click"])
        #expect(savedSteps(["\u{00A0}click\u{00A0}"], at: at) == ["click"])
        #expect(savedSteps(["click"], at: at) == ["click"])
        #expect(savedSteps([" click "], at: at) == ["click"])
        #expect(savedPhrase([" click "], at: at) == "open")
        var store = LearnedShortcutStore()
        #expect(store.save(phrase: "open", steps: ["click"], verified: false, at: at) == .rejected("unverified"))
    }
}

private func savedSteps(_ rawSteps: [String], at: Date) -> [String]? {
    var store = LearnedShortcutStore()
    guard case .saved(let shortcut) = store.save(phrase: "open", steps: rawSteps, verified: true, at: at) else { return nil }
    return shortcut.steps
}

private func savedPhrase(_ rawSteps: [String], at: Date) -> String? {
    var store = LearnedShortcutStore()
    guard case .saved(let shortcut) = store.save(phrase: "open", steps: rawSteps, verified: true, at: at) else { return nil }
    return shortcut.phrase
}
