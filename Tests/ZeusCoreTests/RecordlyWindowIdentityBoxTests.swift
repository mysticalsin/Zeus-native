import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a Recordly window identity. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Recordly window identity box")
struct RecordlyWindowIdentityBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(RecordlyWindowIdentityBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(RecordlyWindowIdentityBox.blankScalars.count == 5)
        #expect(RecordlyWindowIdentityBox.blankScalars.contains(" "))
        #expect(RecordlyWindowIdentityBox.blankScalars.contains("\t"))
        #expect(RecordlyWindowIdentityBox.blankScalars.contains("\n"))
        #expect(RecordlyWindowIdentityBox.blankScalars.contains("\r"))
        #expect(RecordlyWindowIdentityBox.blankScalars.contains("\u{00A0}"))
        #expect(!RecordlyWindowIdentityBox.blankScalars.contains("\u{200B}"))
        #expect(!RecordlyWindowIdentityBox.blankScalars.contains("\u{000B}"))
        #expect(!RecordlyWindowIdentityBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedToken() {
        #expect(RecordlyWindowIdentityBox.trimmedToken("\u{200B}") == "\u{200B}")
        #expect(RecordlyWindowIdentityBox.trimmedToken(" \u{200B} ") == "\u{200B}")
        #expect(RecordlyWindowIdentityBox.trimmedToken("\t\u{200B}\n") == "\u{200B}")
        #expect(RecordlyWindowIdentityBox.trimmedToken("\u{200B}window-token-A") == "\u{200B}window-token-A")
        #expect(RecordlyWindowIdentityBox.trimmedToken("window-token-A\u{200B}") == "window-token-A\u{200B}")
        #expect(RecordlyWindowIdentityBox.trimmedToken(" \t\n\r\u{00A0}") == "")
        #expect(RecordlyWindowIdentityBox.trimmedToken("") == "")
        #expect(RecordlyWindowIdentityBox.trimmedToken("\u{000B}window-token-A") == "\u{000B}window-token-A")
        #expect(RecordlyWindowIdentityBox.trimmedToken("\u{3000}window-token-A") == "\u{3000}window-token-A")
        #expect(RecordlyWindowIdentityBox.trimmedToken(" \twindow-token-A\r\n") == "window-token-A")
        #expect(RecordlyWindowIdentityBox.trimmedToken("\u{00A0}window-token-A\u{00A0}") == "window-token-A")
        #expect(RecordlyWindowIdentityBox.trimmedToken("window\u{00A0}token") == "window\u{00A0}token")
    }

    @Test func aZeroWidthSpaceStaysAsAWindowIdentity() {
        let zwsp = "\u{200B}"
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: zwsp)))
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "\u{200B}window-token-A")))
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: " \u{200B} ")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "   ")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: " \n ")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "\u{00A0}")))
        #expect(!RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: " \t\n\r\u{00A0}")))
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "\u{000B}")))
        #expect(RecordlySourceSelectionBox.hasValidExplicitIdentity(.window(number: 4, identityToken: "\u{3000}")))

        let present = RecordlySourceSelectionBox.Window(number: 9, identityToken: zwsp, isPresent: true)
        let ready = RecordlySourceSelectionBox.resolve(
            intent: .window(number: 9, identityToken: zwsp),
            displayIDs: [],
            windows: [present],
            permission: .granted)
        #expect(ready == .ready(.window(number: 9, identityToken: zwsp)))
        let blank = RecordlySourceSelectionBox.Window(number: 5, identityToken: "   ", isPresent: true)
        let invalid = RecordlySourceSelectionBox.resolve(
            intent: .window(number: 5, identityToken: "   "),
            displayIDs: [],
            windows: [blank],
            permission: .granted)
        #expect(invalid == .invalidIntent(reason: "Choose a window with a valid identity before starting capture."))
        let noBreak = RecordlySourceSelectionBox.Window(number: 5, identityToken: "\u{00A0}", isPresent: true)
        let stripped = RecordlySourceSelectionBox.resolve(
            intent: .window(number: 5, identityToken: "\u{00A0}"),
            displayIDs: [],
            windows: [noBreak],
            permission: .granted)
        #expect(stripped == .invalidIntent(reason: "Choose a window with a valid identity before starting capture."))
        let vertical = RecordlySourceSelectionBox.Window(number: 7, identityToken: "\u{000B}", isPresent: true)
        let kept = RecordlySourceSelectionBox.resolve(
            intent: .window(number: 7, identityToken: "\u{000B}"),
            displayIDs: [],
            windows: [vertical],
            permission: .granted)
        #expect(kept == .ready(.window(number: 7, identityToken: "\u{000B}")))
    }
}
