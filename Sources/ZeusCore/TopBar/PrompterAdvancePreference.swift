import Foundation

/// Slide advance is `prompter.followAdvances`. `prompter.advanceSlides` is the older Boolean.
public enum PrompterAdvancePreference {
    public static let key = "prompter.followAdvances"
    public static let legacyKey = "prompter.advanceSlides"

    /// The settings Boolean when stored, otherwise the legacy Boolean, otherwise off. A read does not write.
    public static func isOn(_ defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        if let legacy = defaults.object(forKey: legacyKey) as? Bool { return legacy }
        return false
    }

    /// Copies the legacy Boolean when the settings key is absent. The legacy key stays.
    @discardableResult
    public static func migrate(_ defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) == nil, let legacy = defaults.object(forKey: legacyKey) as? Bool else { return false }
        defaults.set(legacy, forKey: key)
        return true
    }
}
