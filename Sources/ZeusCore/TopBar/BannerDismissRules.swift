import Foundation

/// URL helper for macOS Notification Settings panes.
public enum NotificationSettingsURL {
    public static func url(for bundleID: String) -> URL? {
        BannerDismissRulesBox.url(for: bundleID)
    }
}

/// Decision rules for auto-dismissing system notification banners.
/// Gated strictly by:
/// 1. Auto-dismiss preference being ON.
/// 2. Accessibility trust being granted.
/// 3. The target app being ticked by the user.
/// 4. Zeus having already mirrored and displayed the notification.
public struct BannerDismissDecision: Equatable, Sendable {
    public static func shouldDismiss(
        app: String,
        autoDismissEnabled: Bool,
        accessibilityTrusted: Bool,
        tickedApps: Set<String>,
        mirroredIDs: Set<Int64>,
        notificationID: Int64?
    ) -> Bool {
        BannerDismissRulesBox.shouldDismiss(
            app: app,
            autoDismissEnabled: autoDismissEnabled,
            accessibilityTrusted: accessibilityTrusted,
            tickedApps: tickedApps,
            mirroredIDs: mirroredIDs,
            notificationID: notificationID)
    }

    public static func parseTickedApps(_ raw: String) -> Set<String> {
        BannerDismissRulesBox.parseTickedApps(raw)
    }

    public static func formatTickedApps(_ apps: Set<String>) -> String {
        BannerDismissRulesBox.formatTickedApps(apps)
    }
}
