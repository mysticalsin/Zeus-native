import CoreGraphics

/// Headless settings capture heights (QA19: avoid clipping tall pages at 2200 pt).
public enum GlanceSettingsSnapshotHeight {
    public static let panelWidth: CGFloat = 680

    public static func height(for section: String) -> CGFloat {
        switch section {
        case "voice": 2600
        case "appearance": 2400
        case "murmure", "dictation": 2600
        case "notifications", "privacy", "diagnostics": 1400
        case "about": 1000
        default: 2200
        }
    }
}
