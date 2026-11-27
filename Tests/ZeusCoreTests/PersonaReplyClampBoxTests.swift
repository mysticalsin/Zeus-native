import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a spoken reply. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Persona reply clamp box")
struct PersonaReplyClampBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(PersonaReplyClampBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(PersonaReplyClampBox.blankScalars.count == 5)
        #expect(PersonaReplyClampBox.blankScalars.contains(" "))
        #expect(PersonaReplyClampBox.blankScalars.contains("\t"))
        #expect(PersonaReplyClampBox.blankScalars.contains("\n"))
        #expect(PersonaReplyClampBox.blankScalars.contains("\r"))
        #expect(PersonaReplyClampBox.blankScalars.contains("\u{00A0}"))
        #expect(!PersonaReplyClampBox.blankScalars.contains("\u{200B}"))
        #expect(!PersonaReplyClampBox.blankScalars.contains("\u{000B}"))
        #expect(!PersonaReplyClampBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTrimmedText() {
        #expect(PersonaReplyClampBox.trimmedText("\u{200B}") == "\u{200B}")
        #expect(PersonaReplyClampBox.trimmedText(" \u{200B} ") == "\u{200B}")
        #expect(PersonaReplyClampBox.trimmedText("\t\u{200B}\n") == "\u{200B}")
        #expect(PersonaReplyClampBox.trimmedText("\u{200B}thanks") == "\u{200B}thanks")
        #expect(PersonaReplyClampBox.trimmedText("thanks\u{200B}") == "thanks\u{200B}")
        #expect(PersonaReplyClampBox.trimmedText(" \t\n\r\u{00A0}") == "")
        #expect(PersonaReplyClampBox.trimmedText("") == "")
        #expect(PersonaReplyClampBox.trimmedText("\u{000B}Always") == "\u{000B}Always")
        #expect(PersonaReplyClampBox.trimmedText("\u{3000}Always") == "\u{3000}Always")
        #expect(PersonaReplyClampBox.trimmedText(" \tAlways\r\n") == "Always")
        #expect(PersonaReplyClampBox.trimmedText("\u{00A0}Always\u{00A0}") == "Always")
        #expect(PersonaReplyClampBox.trimmedText("a\u{00A0}b") == "a\u{00A0}b")
    }

    @Test func aZeroWidthSpaceStaysInTheSpokenClamp() {
        #expect(PersonaReplyClamp.kind(for: "\u{200B}thanks") == .chat)
        #expect(PersonaReplyClamp.kind(for: "\u{200B}") == .chat)
        #expect(PersonaReplyClamp.kind(for: "\u{000B}thanks") == .chat)
        #expect(PersonaReplyClamp.kind(for: "\u{3000}thanks") == .chat)
        #expect(PersonaReplyClamp.kind(for: " \tthanks\n") == .gratitude)
        #expect(PersonaReplyClamp.kind(for: "\u{00A0}thank you\u{00A0}") == .gratitude)
        #expect(PersonaReplyClamp.kind(for: "\rremind me\t") == .action)
        #expect(PersonaReplyClamp.kind(for: " \t\n\r\u{00A0}") == .chat)
        #expect(PersonaReplyClamp.clamp("\u{200B}", maxSentences: 3) == "\u{200B}")
        #expect(PersonaReplyClamp.clamp(" \u{200B} ", maxSentences: 3) == "\u{200B}")
        #expect(PersonaReplyClamp.clamp("\u{200B}Always.", maxSentences: 1) == "\u{200B}Always.")
        #expect(PersonaReplyClamp.clamp(" \t\n\r\u{00A0}", maxSentences: 3) == "")
        #expect(PersonaReplyClamp.clamp("\u{00A0}Always.\u{00A0}", maxSentences: 1) == "Always.")
        #expect(PersonaReplyClamp.clamp("\u{000B}Always.", maxSentences: 1) == "\u{000B}Always.")
        #expect(PersonaReplyClamp.clamp("\u{3000}Always.", maxSentences: 1) == "\u{3000}Always.")
        #expect(PersonaReplyClamp.clamp("Always. Another sentence.", maxSentences: 1) == "Always.")
        #expect(PersonaReplyClamp.maxSentences(transcript: "\u{00A0}explain how octopus hearts work\n", personality: .ultron) == 3)
        let hedged = PersonaReplyClamp.clamp(
            "Operational. The machines are behaving, for now.",
            transcript: "how are you",
            personality: .ultron
        )
        #expect(hedged == "Operational. The machines are behaving.")
    }
}
