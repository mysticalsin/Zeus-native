import Foundation

/// N1: whether Zeus-owned surfaces appear in screen shares and recordings.
public enum ZeusScreenSharePolicy {
    public static let showInSharingKey = "general.showInScreenSharing"
    public static let legacyHideKey = "interview.hide"

    /// Default off: hidden from screen sharing until the user turns visibility on.
    public static func showInScreenSharing(from defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: showInSharingKey) as? Bool { return stored }
        if defaults.object(forKey: legacyHideKey) != nil {
            return !defaults.bool(forKey: legacyHideKey)
        }
        return false
    }

    /// Zeus windows (notch, buddy, trails, HUD overlays) appear in capture when this is true.
    public static func zeusSurfacesVisible(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> Bool {
        showInScreenSharing && !meetingActive && !teleprompterSessionHidden
    }

    /// macOS 27: `.none` can yield blank content in some capture paths; Atticus uses `.readOnly` as a workaround when hiding.
    /// Zeus keeps `.none` when hidden and documents the E2E check under N5/O32.
    public enum CaptureSharingKind: String, Sendable {
        case hidden
        case visibleInShare
    }

    public static func captureKind(visible: Bool) -> CaptureSharingKind {
        visible ? .visibleInShare : .hidden
    }
}
