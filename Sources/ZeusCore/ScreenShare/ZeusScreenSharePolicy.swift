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
    ///
    /// `showInScreenSharing` is off by default, so it is true only when the owner chose "Show to
    /// people I share with". That explicit choice wins over the meeting auto-hide: sharing a screen
    /// is exactly when a meeting is active, and a switch that did nothing then looked broken. With no
    /// choice made, Zeus stays hidden (the default), meeting or not. The teleprompter's own private
    /// session still hides the surfaces that carry private notes.
    public static func zeusSurfacesVisible(showInScreenSharing: Bool, meetingActive: Bool, teleprompterSessionHidden: Bool) -> Bool {
        _ = meetingActive
        return showInScreenSharing && !teleprompterSessionHidden
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
