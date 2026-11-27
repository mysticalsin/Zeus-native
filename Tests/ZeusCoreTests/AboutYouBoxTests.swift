import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a profile field. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("About you box")
struct AboutYouBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(AboutYouBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(AboutYouBox.blankScalars.count == 5)
        #expect(AboutYouBox.blankScalars.contains(" "))
        #expect(AboutYouBox.blankScalars.contains("\t"))
        #expect(AboutYouBox.blankScalars.contains("\n"))
        #expect(AboutYouBox.blankScalars.contains("\r"))
        #expect(AboutYouBox.blankScalars.contains("\u{00A0}"))
        #expect(!AboutYouBox.blankScalars.contains("\u{200B}"))
        #expect(!AboutYouBox.blankScalars.contains("\u{000B}"))
        #expect(!AboutYouBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInAField() {
        #expect(AboutYouBox.trimmedField("\u{200B}") == "\u{200B}")
        #expect(AboutYouBox.trimmedField(" \u{200B} ") == "\u{200B}")
        #expect(AboutYouBox.trimmedField("\t\u{200B}\n") == "\u{200B}")
        #expect(AboutYouBox.trimmedField("\u{200B}Tony") == "\u{200B}Tony")
        #expect(AboutYouBox.trimmedField("Tony\u{200B}") == "Tony\u{200B}")
        #expect(AboutYouBox.trimmedField(" \t\n\r\u{00A0}") == "")
        #expect(AboutYouBox.trimmedField("\u{000B}Tony") == "\u{000B}Tony")
        #expect(AboutYouBox.trimmedField("\u{3000}Tony") == "\u{3000}Tony")
        #expect(AboutYouBox.trimmedField(" \tTony\r\n") == "Tony")
        #expect(AboutYouBox.trimmedField("\u{00A0}Tony\u{00A0}") == "Tony")
    }

    @Test func aZeroWidthSpaceStillCompletesAProfile() {
        let created = Date(timeIntervalSince1970: 1_793_475_612)
        let zone = TimeZone(identifier: "UTC")!
        let kept = AboutYouProfile(name: " \u{200B} ", work: "\u{200B}", helpWith: " \t\n\r\u{00A0}", notes: "\u{000B}kept")
        #expect(kept.isComplete)
        let text = kept.markdown(created: created, timeZone: zone)
        #expect(text.contains("# About \u{200B}\n"))
        #expect(text.contains("## Work\n\n\u{200B}\n"))
        #expect(!text.contains("## What ZEUS should help with"))
        #expect(text.contains("## Notes\n\n\u{000B}kept\n"))

        #expect(!AboutYouProfile(name: "").isComplete)
        #expect(!AboutYouProfile(name: " \t\n\r\u{00A0}").isComplete)
        #expect(!AboutYouProfile(name: "\u{00A0}").isComplete)

        let mixed = AboutYouProfile(name: " \tAda\r\n", work: " \t\n\r\u{00A0}", helpWith: "\u{3000}", notes: " \tnotes\r\n")
        #expect(mixed.isComplete)
        let body = mixed.markdown(created: created, timeZone: zone)
        #expect(body.contains("# About Ada\n"))
        #expect(!body.contains("## Work"))
        #expect(body.contains("## What ZEUS should help with\n\n\u{3000}\n"))
        #expect(body.contains("## Notes\n\nnotes\n"))
        #expect(AboutYouProfile(name: "\u{000B}").isComplete)
        #expect(AboutYouProfile(name: "\u{3000}").isComplete)
    }
}
