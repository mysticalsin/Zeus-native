import Foundation

/// N1: whether Zeus-owned surfaces appear in screen shares and recordings.
public enum ZeusScreenSharePolicy {
    public static let showInSharingKey = "general.showInScreenSharing"
    /// The string the settings store writes (`opt.` plus the catalog id).
    public static let storedKey = "opt.general.showInScreenSharing"
    public static let legacyHideKey = "interview.hide"

    /// The live string wins. Otherwise a Boolean at the bare key, otherwise the inverse of an
    /// explicit hide flag. A missing pair stays hidden. A read does not write.
    public static func showInScreenSharing(from defaults: UserDefaults) -> Bool {
        switch defaults.string(forKey: storedKey) {
        case "true": return true
        case "false": return false
        default: break
        }
        if let stored = defaults.object(forKey: showInSharingKey) as? Bool { return stored }
        if defaults.object(forKey: legacyHideKey) != nil {
            return !defaults.bool(forKey: legacyHideKey)
        }
        return false
    }

    /// Copies an older Boolean into the live string when that string is absent. Does not delete
    /// the older key and does not overwrite a string that is already stored.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: storedKey) == nil else { return false }
        if let stored = defaults.object(forKey: showInSharingKey) as? Bool {
            defaults.set(stored ? "true" : "false", forKey: storedKey)
            return true
        }
        if defaults.object(forKey: legacyHideKey) != nil {
            let show = !defaults.bool(forKey: legacyHideKey)
            defaults.set(show ? "true" : "false", forKey: storedKey)
            return true
        }
        return false
    }

    /// Writes the live string and the legacy hide flag to the same choice. Neither key is removed.
    public static func setShown(_ shown: Bool, defaults: UserDefaults) {
        defaults.set(shown ? "true" : "false", forKey: storedKey)
        defaults.set(!shown, forKey: legacyHideKey)
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
