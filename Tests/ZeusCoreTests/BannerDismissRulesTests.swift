import Foundation
import Testing
@testable import ZeusCore

@Suite("BannerDismissRules")
struct BannerDismissRulesTests {
    @Test func buildsNotificationSettingsURL() {
        let appURL = NotificationSettingsURL.url(for: "com.apple.MobileSMS")
        #expect(appURL?.absoluteString == "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.apple.MobileSMS")

        let emptyURL = NotificationSettingsURL.url(for: "")
        #expect(emptyURL?.absoluteString == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    @Test func dismissDecisionRespectsAllGates() {
        let ticked: Set<String> = ["com.tinyspeck.slackmacgap", "com.apple.mobilesms"]
        let mirrored: Set<Int64> = [101, 102, 103]

        // All gates open: should dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.apple.MobileSMS",
                autoDismissEnabled: true,
                accessibilityTrusted: true,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: 101
            ) == true
        )

        // Feature switch off: should not dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.apple.MobileSMS",
                autoDismissEnabled: false,
                accessibilityTrusted: true,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: 101
            ) == false
        )

        // Accessibility not trusted: should not dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.apple.MobileSMS",
                autoDismissEnabled: true,
                accessibilityTrusted: false,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: 101
            ) == false
        )

        // Unticked app: should not dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.google.Chrome",
                autoDismissEnabled: true,
                accessibilityTrusted: true,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: 101
            ) == false
        )

        // Notification not yet mirrored: should not dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.apple.MobileSMS",
                autoDismissEnabled: true,
                accessibilityTrusted: true,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: 999
            ) == false
        )

        // Missing notification ID: should not dismiss
        #expect(
            BannerDismissDecision.shouldDismiss(
                app: "com.apple.MobileSMS",
                autoDismissEnabled: true,
                accessibilityTrusted: true,
                tickedApps: ticked,
                mirroredIDs: mirrored,
                notificationID: nil
            ) == false
        )
    }

    @Test func parsesAndFormatsTickedApps() {
        let raw = "com.apple.MobileSMS, com.tinyspeck.slackmacgap, , com.apple.mail "
        let parsed = BannerDismissDecision.parseTickedApps(raw)
        #expect(parsed.contains("com.apple.mobilesms"))
        #expect(parsed.contains("com.tinyspeck.slackmacgap"))
        #expect(parsed.contains("com.apple.mail"))
        #expect(parsed.count == 3)

        let formatted = BannerDismissDecision.formatTickedApps(parsed)
        #expect(formatted == "com.apple.mail, com.apple.mobilesms, com.tinyspeck.slackmacgap")
    }
}
