import Foundation

/// Whether Scribe may read participant names from the call window. On from the first launch, but only
/// while the owner's own Accessibility grant exists: this never asks for it (`docs/FIRST-RUN-DEFAULTS.md`).
public enum ScribeCallWindowNamesPolicy {
    public static let settingID = "scribe.callWindowNames"

    /// The owner's switch. Untouched installs have it on.
    public static func isOn(defaults: UserDefaults = .standard) -> Bool {
        FeatureSettings.bool(settingID, default: true, defaults: defaults)
    }

    /// Names are read only when the switch is on and Accessibility is already granted.
    public static func isActive(accessibilityGranted: Bool, defaults: UserDefaults = .standard) -> Bool {
        accessibilityGranted && isOn(defaults: defaults)
    }
}
