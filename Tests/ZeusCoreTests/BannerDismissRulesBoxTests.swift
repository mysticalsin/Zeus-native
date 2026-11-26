import Foundation
import Testing
@testable import ZeusCore

@Suite("Banner dismiss rules box")
struct BannerDismissRulesBoxTests {
    private let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

    @Test func thePaneIsTheNotificationsSettingsExtension() {
        #expect(BannerDismissRulesBox.settingsPane == pane)
    }

    @Test func aBundleIDOpensThatAppsNotificationPane() {
        let url = BannerDismissRulesBox.url(for: "com.apple.MobileSMS")
        #expect(url?.absoluteString == "\(pane)?id=com.apple.MobileSMS")
    }

    @Test func aBlankBundleIDOpensThePaneWithoutAQuery() {
        #expect(BannerDismissRulesBox.url(for: "")?.absoluteString == pane)
        #expect(BannerDismissRulesBox.url(for: " \n\t ")?.absoluteString == pane)
    }

    @Test func theBundleIDIsTrimmedBeforeItIsPlacedInTheQuery() {
        let url = BannerDismissRulesBox.url(for: "  com.apple.mail  ")
        #expect(url?.absoluteString == "\(pane)?id=com.apple.mail")
    }

    @Test func everyOpenGateDismissesTheMirroredBanner() {
        #expect(BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS",
            autoDismissEnabled: true,
            accessibilityTrusted: true,
            tickedApps: ["com.apple.mobilesms"],
            mirroredIDs: [101],
            notificationID: 101
        ))
    }

    @Test func thePreferenceAndTheAccessibilityTrustBothHaveToBeOn() {
        let ticked: Set<String> = ["com.apple.mobilesms"]
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: false, accessibilityTrusted: true,
            tickedApps: ticked, mirroredIDs: [101], notificationID: 101))
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: false,
            tickedApps: ticked, mirroredIDs: [101], notificationID: 101))
        #expect(BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ticked, mirroredIDs: [101], notificationID: 101))
    }

    @Test func aBlankAppIsNotATickedApp() {
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "   ", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["", "   "], mirroredIDs: [1], notificationID: 1))
        #expect(BannerDismissRulesBox.shouldDismiss(
            app: "  Com.Apple.Mail  ", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["com.apple.mail"], mirroredIDs: [7], notificationID: 7))
    }

    @Test func theRawAppStringMatchesWhenTheLowercasedIDIsAbsent() {
        #expect(BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["com.apple.MobileSMS"], mirroredIDs: [4], notificationID: 4))
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "  com.apple.MobileSMS  ", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["com.apple.MobileSMS"], mirroredIDs: [4], notificationID: 4))
    }

    @Test func anUntickedAppStaysOnScreen() {
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.google.Chrome", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["com.apple.mobilesms"], mirroredIDs: [101], notificationID: 101))
        #expect(BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ["com.apple.mobilesms"], mirroredIDs: [101], notificationID: 101))
    }

    @Test func aMissingOrUnmirroredIDStaysOnScreen() {
        let ticked: Set<String> = ["com.apple.mobilesms"]
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ticked, mirroredIDs: [101], notificationID: nil))
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ticked, mirroredIDs: [101], notificationID: 999))
        #expect(!BannerDismissRulesBox.shouldDismiss(
            app: "com.apple.MobileSMS", autoDismissEnabled: true, accessibilityTrusted: true,
            tickedApps: ticked, mirroredIDs: [], notificationID: 101))
        #expect(BannerDismissRulesBox.settingsPane == pane)
    }

    @Test func tickedAppsDropBlanksAndLowercaseEachID() {
        let parsed = BannerDismissRulesBox.parseTickedApps("com.apple.MobileSMS, com.tinyspeck.slackmacgap, , com.apple.mail ")
        #expect(parsed == ["com.apple.mobilesms", "com.tinyspeck.slackmacgap", "com.apple.mail"])
        #expect(BannerDismissRulesBox.parseTickedApps(" , , ").isEmpty)
        #expect(BannerDismissRulesBox.parseTickedApps("").isEmpty)
    }

    @Test func tickedAppsFormatSortsAndJoinsWithAComma() {
        let formatted = BannerDismissRulesBox.formatTickedApps(["com.tinyspeck.slackmacgap", "com.apple.mail", "com.apple.mobilesms"])
        #expect(formatted == "com.apple.mail, com.apple.mobilesms, com.tinyspeck.slackmacgap")
        #expect(BannerDismissRulesBox.formatTickedApps([]).isEmpty)
        #expect(BannerDismissRulesBox.formatTickedApps(["com.apple.mail"]) == "com.apple.mail")
    }
}
