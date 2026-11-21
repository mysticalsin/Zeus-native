import Foundation

/// L5: physical pointer actuation (synthetic clicks) stays off unless Tony turns it on.
public enum PhysicalPointerSettings {
    /// Legacy Bool. Settings never writes this key.
    public static let defaultsKey = "present.physicalPointer"
    /// What `SettingsStore` writes: the string `true` or `false`.
    public static let catalogKey = "opt.present.physicalPointer"

    public static var enabled: Bool {
        let defaults = UserDefaults.standard
        return enabled(boolValue: defaults.object(forKey: defaultsKey) as? Bool,
                       catalogText: defaults.string(forKey: catalogKey))
    }

    /// The preference decision is independent of its host-backed storage.
    public static func enabled(storedValue: Bool?) -> Bool { enabled(boolValue: storedValue, catalogText: nil) }

    /// A catalog string of `true` or `false` wins. Anything else falls back to the legacy Bool, then off.
    public static func enabled(boolValue: Bool?, catalogText: String?) -> Bool {
        if let text = catalogText?.trimmingCharacters(in: .whitespacesAndNewlines), text == "true" || text == "false" {
            return text == "true"
        }
        return boolValue ?? false
    }
}
