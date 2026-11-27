import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a stored language choice. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("App language pin box")
struct AppLanguagePinBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AppLanguagePinBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AppLanguagePinBox.blankScalars.count == 5)
        #expect(AppLanguagePinBox.blankScalars.contains(" "))
        #expect(AppLanguagePinBox.blankScalars.contains("\t"))
        #expect(AppLanguagePinBox.blankScalars.contains("\n"))
        #expect(AppLanguagePinBox.blankScalars.contains("\r"))
        #expect(AppLanguagePinBox.blankScalars.contains("\u{00A0}"))
        #expect(!AppLanguagePinBox.blankScalars.contains("\u{200B}"))
        #expect(!AppLanguagePinBox.blankScalars.contains("\u{000B}"))
        #expect(!AppLanguagePinBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedChoice() {
        #expect(AppLanguagePinBox.trimmedChoice("\u{200B}") == "\u{200B}")
        #expect(AppLanguagePinBox.trimmedChoice(" \u{200B} ") == "\u{200B}")
        #expect(AppLanguagePinBox.trimmedChoice("\t\u{200B}\n") == "\u{200B}")
        #expect(AppLanguagePinBox.trimmedChoice("\u{200B}English") == "\u{200B}English")
        #expect(AppLanguagePinBox.trimmedChoice("English\u{200B}") == "English\u{200B}")
        #expect(AppLanguagePinBox.trimmedChoice(" \t\n\r\u{00A0}") == "")
        #expect(AppLanguagePinBox.trimmedChoice("") == "")
        #expect(AppLanguagePinBox.trimmedChoice("\u{000B}English") == "\u{000B}English")
        #expect(AppLanguagePinBox.trimmedChoice("\u{3000}English") == "\u{3000}English")
        #expect(AppLanguagePinBox.trimmedChoice(" \tEnglish\r\n") == "English")
        #expect(AppLanguagePinBox.trimmedChoice("\u{00A0}English\u{00A0}") == "English")
        #expect(AppLanguagePinBox.trimmedChoice("too\u{00A0}many") == "too\u{00A0}many")
    }

    @Test func aZeroWidthSpaceDoesNotPinEnglish() {
        #expect(AppLanguagePin.resolve(stored: "\u{200B}English", systemLanguages: ["fr"]) == .french)
        #expect(AppLanguagePin.resolve(stored: " \u{200B}English ", systemLanguages: ["fr"]) == .french)
        #expect(AppLanguagePin.resolve(stored: "\u{200B}", systemLanguages: ["fr"]) == .french)
        #expect(AppLanguagePin.resolve(stored: "\u{000B}English", systemLanguages: ["pt"]) == .portuguese)
        #expect(AppLanguagePin.resolve(stored: "\u{3000}English", systemLanguages: ["es"]) == .spanish)
        #expect(AppLanguagePin.resolve(stored: " \t\n\r\u{00A0}English\u{00A0}\n", systemLanguages: ["fr"]) == .english)
        #expect(AppLanguagePin.resolve(stored: "English", systemLanguages: ["pt-BR"]) == .english)
        #expect(AppLanguagePin.resolve(stored: " \t\n\r\u{00A0}", systemLanguages: ["es"]) == .spanish)
        #expect(AppLanguagePin.resolve(stored: nil, systemLanguages: ["fr"]) == .french)
        #expect(AppLanguagePin.resolve(stored: "System language", systemLanguages: ["pt-BR"]) == .portuguese)
    }
}
