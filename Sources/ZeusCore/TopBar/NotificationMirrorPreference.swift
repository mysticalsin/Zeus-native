import Foundation

/// The notch mirror is the Boolean `notifications.mirror`. The catalog id `notify.mirror` was stored
/// as the string `opt.notify.mirror`.
public enum NotificationMirrorPreference {
    public static let key = "notifications.mirror"
    public static let legacyKey = "opt.notify.mirror"

    /// The Boolean when one was stored, otherwise a legacy "true". A read does not write.
    public static func isOn(_ defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        return defaults.string(forKey: legacyKey) == "true"
    }

    /// Copies a legacy string into the Boolean when the Boolean is absent. The string stays.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) == nil else { return false }
        switch defaults.string(forKey: legacyKey) {
        case "true":
            defaults.set(true, forKey: key)
            return true
        case "false":
            defaults.set(false, forKey: key)
            return true
        default:
            return false
        }
    }

    /// Writes the Boolean and the same choice as the legacy string.
    public static func set(_ on: Bool, defaults: UserDefaults) {
        defaults.set(on, forKey: key)
        defaults.set(on ? "true" : "false", forKey: legacyKey)
    }
}
