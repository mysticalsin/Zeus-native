import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays on the app trim inside `BannerDismissRulesBox.shouldDismiss`.
/// These tests name the blanks. Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Banner dismiss app box")
struct BannerDismissAppBoxTests {
    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BannerDismissAppBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BannerDismissAppBox.blankScalars.count == 5)
        #expect(BannerDismissAppBox.blankScalars.contains(" "))
        #expect(BannerDismissAppBox.blankScalars.contains("\t"))
        #expect(BannerDismissAppBox.blankScalars.contains("\n"))
        #expect(BannerDismissAppBox.blankScalars.contains("\r"))
        #expect(BannerDismissAppBox.blankScalars.contains("\u{00A0}"))
        #expect(!BannerDismissAppBox.blankScalars.contains("\u{200B}"))
        #expect(!BannerDismissAppBox.blankScalars.contains("\u{000B}"))
        #expect(!BannerDismissAppBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysOnTheTrimmedApp() {
        #expect(BannerDismissAppBox.trimmedApp("\u{200B}") == "\u{200B}")
        #expect(BannerDismissAppBox.trimmedApp(" \u{200B} ") == "\u{200B}")
        #expect(BannerDismissAppBox.trimmedApp("\t\u{200B}\n") == "\u{200B}")
        #expect(BannerDismissAppBox.trimmedApp("\u{200B}Mail") == "\u{200B}Mail")
        #expect(BannerDismissAppBox.trimmedApp("Mail\u{200B}") == "Mail\u{200B}")
        #expect(BannerDismissAppBox.trimmedApp(" \t\n\r\u{00A0}") == "")
        #expect(BannerDismissAppBox.trimmedApp("") == "")
        #expect(BannerDismissAppBox.trimmedApp("\u{000B}Mail") == "\u{000B}Mail")
        #expect(BannerDismissAppBox.trimmedApp("\u{3000}Mail") == "\u{3000}Mail")
        #expect(BannerDismissAppBox.trimmedApp(" \tMail\r\n") == "Mail")
        #expect(BannerDismissAppBox.trimmedApp("\u{00A0}Mail\u{00A0}") == "Mail")
        #expect(BannerDismissAppBox.trimmedApp("Mail") == "Mail")
        #expect(BannerDismissAppBox.trimmedApp("Ma\u{200B}il") == "Ma\u{200B}il")
        #expect(BannerDismissAppBox.trimmedApp("\n") == "")
        #expect(BannerDismissAppBox.trimmedApp("\r") == "")
        #expect(BannerDismissAppBox.trimmedApp("\n\u{200B}\r") == "\u{200B}")
    }

    @Test func aZeroWidthSpaceStaysOnTheDismissedApp() {
        #expect(dismiss("\u{200B}", ticked: ["\u{200b}"]))
        #expect(dismiss(" \u{200B} ", ticked: ["\u{200b}"]))
        #expect(dismiss("\t\u{200B}\n", ticked: ["\u{200b}"]))
        #expect(!dismiss("\u{200B}Mail", ticked: ["mail"]))
        #expect(dismiss("\u{200B}Mail", ticked: ["\u{200b}mail"]))
        #expect(dismiss("Mail\u{200B}", ticked: ["mail\u{200b}"]))
        #expect(!dismiss("Mail\u{200B}", ticked: ["mail"]))
        #expect(dismiss("Ma\u{200B}il", ticked: ["ma\u{200b}il"]))
        #expect(!dismiss("Ma\u{200B}il", ticked: ["mail"]))
        #expect(!dismiss("\u{200B}", ticked: ["mail"]))
        #expect(!dismiss("   ", ticked: ["", "   ", "\u{200b}"]))
        #expect(!dismiss(" \t\n\r\u{00A0}", ticked: ["mail"]))
        #expect(dismiss("\u{00A0}Mail\u{00A0}", ticked: ["mail"]))
        #expect(dismiss(" \tMail\r\n", ticked: ["mail"]))
        #expect(!dismiss("\u{3000}Mail", ticked: ["mail"]))
        #expect(dismiss("\u{3000}Mail", ticked: ["\u{3000}mail"]))
        #expect(!dismiss("\u{000B}Mail", ticked: ["mail"]))
        #expect(dismiss("\u{000B}Mail", ticked: ["\u{000b}mail"]))
        #expect(dismiss("Mail", ticked: ["mail"]))
        #expect(dismiss("  Com.Apple.Mail  ", ticked: ["com.apple.mail"]))
        #expect(!dismiss("\u{200B}Mail", ticked: ["\u{200b}mail"], enabled: false))
        #expect(!dismiss("\u{200B}Mail", ticked: ["\u{200b}mail"], trusted: false))
        #expect(!dismiss("\u{200B}Mail", ticked: ["\u{200b}mail"], id: nil))
        #expect(dismiss("\u{200B}Mail", ticked: ["\u{200B}Mail"]))
        #expect(!dismiss("\n\u{200B}\r", ticked: ["mail"]))
        #expect(dismiss("\n\u{200B}\r", ticked: ["\u{200b}"]))
    }

    private func dismiss(
        _ app: String,
        ticked: Set<String>,
        enabled: Bool = true,
        trusted: Bool = true,
        mirrored: Set<Int64> = [1],
        id: Int64? = 1
    ) -> Bool {
        BannerDismissRulesBox.shouldDismiss(
            app: app,
            autoDismissEnabled: enabled,
            accessibilityTrusted: trusted,
            tickedApps: ticked,
            mirroredIDs: mirrored,
            notificationID: id
        )
    }
}
