import Foundation

/// Notch and window share `prompter.speed` and `prompter.size`. The window's older keys are
/// `prompterWindow.speed` and `prompterWindow.font`.
public enum PrompterMetricsPreference {
    public static let speedKey = "prompter.speed"
    public static let sizeKey = "prompter.size"
    public static let legacySpeedKey = "prompterWindow.speed"
    public static let legacySizeKey = "prompterWindow.font"
    public static let defaultSpeed = 32.0
    public static let defaultSize = 22.0

    public static func speed(_ defaults: UserDefaults) -> Double {
        if let stored = defaults.object(forKey: speedKey) as? Double { return stored }
        if let legacy = defaults.object(forKey: legacySpeedKey) as? Double { return legacy }
        return defaultSpeed
    }

    public static func size(_ defaults: UserDefaults) -> Double {
        if let stored = defaults.object(forKey: sizeKey) as? Double { return stored }
        if let legacy = defaults.object(forKey: legacySizeKey) as? Double { return legacy }
        return defaultSize
    }

    /// Copies a window-only value into the canonical key when that key is absent. An existing
    /// canonical value is left alone, and the window key is not deleted.
    public static func migrate(_ defaults: UserDefaults) {
        if defaults.object(forKey: speedKey) == nil, let legacy = defaults.object(forKey: legacySpeedKey) as? Double {
            defaults.set(legacy, forKey: speedKey)
        }
        if defaults.object(forKey: sizeKey) == nil, let legacy = defaults.object(forKey: legacySizeKey) as? Double {
            defaults.set(legacy, forKey: sizeKey)
        }
    }

    public static func setSpeed(_ value: Double, defaults: UserDefaults) {
        defaults.set(value, forKey: speedKey)
        defaults.set(value, forKey: legacySpeedKey)
    }

    public static func setSize(_ value: Double, defaults: UserDefaults) {
        defaults.set(value, forKey: sizeKey)
        defaults.set(value, forKey: legacySizeKey)
    }
}
