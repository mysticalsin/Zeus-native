import Foundation
import Testing
@testable import ZeusCore

/// A zero-width space stays in a notification bundle id. These tests name the blanks.
/// Linux `CharacterSet.whitespacesAndNewlines` treats U+200B as blank.
@Suite("Banner bundle blank box")
struct BannerBundleBlankBoxTests {
    private static let pane = BannerDismissRulesBox.settingsPane

    @Test func blankScalarsAreSpaceTabNewlineCarriageReturnAndNoBreakSpace() {
        #expect(BannerBundleBlankBox.blankScalars == Set<Unicode.Scalar>([
            " ", "\t", "\n", "\r", "\u{00A0}",
        ]))
        #expect(BannerBundleBlankBox.blankScalars.count == 5)
        #expect(BannerBundleBlankBox.blankScalars.contains(" "))
        #expect(BannerBundleBlankBox.blankScalars.contains("\t"))
        #expect(BannerBundleBlankBox.blankScalars.contains("\n"))
        #expect(BannerBundleBlankBox.blankScalars.contains("\r"))
        #expect(BannerBundleBlankBox.blankScalars.contains("\u{00A0}"))
        #expect(!BannerBundleBlankBox.blankScalars.contains("\u{200B}"))
        #expect(!BannerBundleBlankBox.blankScalars.contains("\u{000B}"))
        #expect(!BannerBundleBlankBox.blankScalars.contains("\u{3000}"))
    }

    @Test func aZeroWidthSpaceStaysInTheTrimmedBundle() {
        #expect(BannerBundleBlankBox.trimmedBundle("\u{200B}") == "\u{200B}")
        #expect(BannerBundleBlankBox.trimmedBundle(" \u{200B} ") == "\u{200B}")
        #expect(BannerBundleBlankBox.trimmedBundle("\t\u{200B}\n") == "\u{200B}")
        #expect(BannerBundleBlankBox.trimmedBundle("\u{200B}com.apple.mail") == "\u{200B}com.apple.mail")
        #expect(BannerBundleBlankBox.trimmedBundle("com.apple.mail\u{200B}") == "com.apple.mail\u{200B}")
        #expect(BannerBundleBlankBox.trimmedBundle(" \t\n\r\u{00A0}") == "")
        #expect(BannerBundleBlankBox.trimmedBundle("") == "")
        #expect(BannerBundleBlankBox.trimmedBundle("\u{000B}com.apple.mail") == "\u{000B}com.apple.mail")
        #expect(BannerBundleBlankBox.trimmedBundle("\u{3000}com.apple.mail") == "\u{3000}com.apple.mail")
        #expect(BannerBundleBlankBox.trimmedBundle(" \tcom.apple.mail\r\n") == "com.apple.mail")
        #expect(BannerBundleBlankBox.trimmedBundle("\u{00A0}com.apple.mail\u{00A0}") == "com.apple.mail")
        #expect(BannerBundleBlankBox.trimmedBundle("com.apple.\u{00A0}mail") == "com.apple.\u{00A0}mail")
    }

    @Test func aZeroWidthSpaceDoesNotOpenTheBareNotificationsPane() {
        let bare = BannerDismissRulesBox.url(for: "com.apple.mail")?.absoluteString
        #expect(BannerDismissRulesBox.url(for: "\u{200B}")?.absoluteString != Self.pane)
        #expect(BannerDismissRulesBox.url(for: "\u{200B}")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: "\u{200B}com.apple.mail")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: "com.apple.mail\u{200B}")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: " \u{200B}com.apple.mail ")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: "  com.apple.mail  ")?.absoluteString == bare)
        #expect(BannerDismissRulesBox.url(for: "\ncom.apple.mail\t")?.absoluteString == bare)
        #expect(BannerDismissRulesBox.url(for: "\u{00A0}com.apple.mail\u{00A0}")?.absoluteString == bare)
        #expect(BannerDismissRulesBox.url(for: "\u{000B}com.apple.mail")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: "\u{3000}com.apple.mail")?.absoluteString != bare)
        #expect(BannerDismissRulesBox.url(for: "   ")?.absoluteString == Self.pane)
        #expect(BannerDismissRulesBox.url(for: " \t\n\r\u{00A0}")?.absoluteString == Self.pane)
        #expect(BannerDismissRulesBox.url(for: "")?.absoluteString == Self.pane)
    }
}
