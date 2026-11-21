import Foundation

/// The notch mirror is the Boolean `notifications.mirror`. The catalog id `notify.mirror` was stored
/// as the string `opt.notify.mirror`.
public enum NotificationMirrorPreference {
    public static let key = "notifications.mirror"
    public static let legacyKey = "opt.notify.mirror"

    /// The Boolean when one was stored. A legacy string never turns the mirror on. A read does not write.
    public static func isOn(_ defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        return false
    }

    /// Copies a legacy `"false"` into the Boolean when the Boolean is absent. The string stays.
    /// A legacy `"true"` is left untouched, so an upgrade cannot turn mirroring on.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) == nil else { return false }
        switch defaults.string(forKey: legacyKey) {
        case "false", "true":
            set(false, defaults: defaults)
            return true
        default:
            return false
        }
    }

    /// An imported value enables the mirror when it is boolean true or the string `"true"`.
    public static func importWouldEnable(_ value: Any) -> Bool {
        if let flag = value as? Bool { return flag }
        if let text = value as? String { return text == "true" }
        return false
    }

    /// Applies an imported value. True is refused and nothing is written. False is stored.
    /// Anything else is ignored. An import cannot enable the mirror.
    @discardableResult
    public static func applyImport(_ value: Any, defaults: UserDefaults) -> Bool {
        if importWouldEnable(value) { return false }
        if let flag = value as? Bool, flag == false {
            set(false, defaults: defaults)
            return true
        }
        if let text = value as? String, text == "false" {
            set(false, defaults: defaults)
            return true
        }
        return false
    }

    /// Writes the Boolean and the same choice as the legacy string.
    public static func set(_ on: Bool, defaults: UserDefaults) {
        defaults.set(on, forKey: key)
        defaults.set(on ? "true" : "false", forKey: legacyKey)
    }
}
