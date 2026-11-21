import Foundation

/// The notch waveform and the Media page share one Boolean, `topBar.musicWings`.
/// Older Media-page writes live at `opt.topBar.musicWings` as the strings "true" and "false".
public enum MusicWingsPreference {
    public static let id = "topBar.musicWings"
    public static let key = id
    public static let legacyKey = "opt.topBar.musicWings"

    /// The Boolean when one was stored, otherwise a legacy "true" or "false", otherwise on.
    /// A read does not write.
    public static func isOn(_ defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        switch defaults.string(forKey: legacyKey) {
        case "true": return true
        case "false": return false
        default: return true
        }
    }

    /// Writes the Boolean and the same choice as the legacy string. Neither key is removed.
    public static func set(_ on: Bool, defaults: UserDefaults) {
        defaults.set(on, forKey: key)
        defaults.set(on ? "true" : "false", forKey: legacyKey)
    }

    /// Copies a legacy string into the Boolean when the Boolean has never been stored.
    /// An existing Boolean is left as it is, and the legacy string is left as it is.
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
}
