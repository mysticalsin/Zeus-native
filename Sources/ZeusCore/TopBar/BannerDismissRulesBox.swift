import Foundation

/// Notification Settings pane and the gates that auto-dismiss a mirrored banner.
/// The caller supplies the preference, the accessibility trust, the ticked apps, and the mirrored ids.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum BannerDismissRulesBox {
    public static let settingsPane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

    /// A blank id opens the Notifications pane. Any other id is trimmed and passed as the `id` query.
    public static func url(for bundleID: String) -> URL? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return URL(string: settingsPane) }
        return URL(string: "\(settingsPane)?id=\(trimmed)")
    }

    /// All four gates have to be open. The app matches a ticked id after trim and lowercasing, or the raw
    /// string the caller passed. A missing id, or one Zeus has not mirrored, stays on screen.
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

    /// Comma-separated bundle ids. Each piece is trimmed and lowercased. Empty pieces are dropped.
    public static func parseTickedApps(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
    }

    /// Sorted bundle ids, joined with a comma and a space. An empty set is an empty string.
    public static func formatTickedApps(_ apps: Set<String>) -> String {
        apps.sorted().joined(separator: ", ")
    }
}
