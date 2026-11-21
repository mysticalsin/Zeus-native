import Foundation

/// N1: whether Zeus-owned surfaces appear in screen shares and recordings.
public enum ZeusScreenSharePolicy {
    public static let showInSharingKey = "general.showInScreenSharing"
    /// The string the settings store writes (`opt.` plus the catalog id).
    public static let storedKey = "opt.general.showInScreenSharing"
    public static let legacyHideKey = "interview.hide"

    /// Who is writing the screen-share choice. Only `person` may turn showing on.
    /// Import, reset, agent, and migration may turn it off. That is a downgrade: Zeus becomes
    /// harder to see in a share, never easier. A legacy visible flag is not promoted to "true".
    public enum WriteOrigin: Sendable, Equatable {
        case person, reset, importFile, agent, migration
    }

    /// True when this origin may persist `show == true`. A request to hide is always persisted.
    public static func persistsShow(requestedTrue: Bool, origin: WriteOrigin) -> Bool {
        if requestedTrue { return origin == .person }
        return true
    }

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

    /// Copies an older hidden choice into the live string when that string is absent.
    /// Does not delete the older key and does not overwrite a string that is already stored.
    ///
    /// Downgrade: migration never writes `"true"`. A legacy Boolean that would show, or a legacy
    /// hide flag of false, is stored as hidden (`"false"`). An absent pair is left absent, so a
    /// migration does not invent a choice. A live string already set by a person is left alone,
    /// including `"true"`.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: storedKey) == nil else { return false }
        let hasLegacyBoolean = defaults.object(forKey: showInSharingKey) as? Bool != nil
        let hasLegacyHide = defaults.object(forKey: legacyHideKey) != nil
        guard hasLegacyBoolean || hasLegacyHide else { return false }
        defaults.set("false", forKey: storedKey)
        return true
    }

    /// Forgets `keys`. When `interview.hide` is among them, the live show string is forced to
    /// `"false"` so dropping the legacy flag cannot leave Zeus visible.
    public static func reset(_ keys: [String], defaults: UserDefaults) {
        let forcesHidden = keys.contains(legacyHideKey)
        for key in keys { defaults.removeObject(forKey: key) }
        if forcesHidden { defaults.set("false", forKey: storedKey) }
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
