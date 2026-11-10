import Foundation

/// URL helper for macOS Notification Settings panes.
public enum NotificationSettingsURL {
    public static func url(for bundleID: String) -> URL? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        }
        return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(trimmed)")
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
        guard autoDismissEnabled else { return false }
        guard accessibilityTrusted else { return false }
        let cleanApp = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanApp.isEmpty else { return false }
        let matchesApp = tickedApps.contains(cleanApp) || tickedApps.contains(app)
        guard matchesApp else { return false }
        guard let id = notificationID, mirroredIDs.contains(id) else { return false }
        return true
    }

    public static func parseTickedApps(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    public static func formatTickedApps(_ apps: Set<String>) -> String {
        apps.sorted().joined(separator: ", ")
    }
}
