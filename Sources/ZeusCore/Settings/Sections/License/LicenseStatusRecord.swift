import Foundation

/// Non-secret license status kept by the settings store. The license key is not one of these.
public enum LicenseStatusRecord {
    public static let activationState = SettingsKeyContribution(
        id: "license.activationState", defaultValue: "unlicensed", kind: .text, policy: .localOnly
    )
    public static let lastValidated = SettingsKeyContribution(
        id: "license.lastValidated", defaultValue: "", kind: .text, policy: .localOnly
    )

    public static var contributions: [SettingsKeyContribution] { [activationState, lastValidated] }

    /// A value that still contains a license key is stored as empty.
    public static func sanitized(_ value: String) -> String {
        let cleaned = LicenseKeyPrivacy.scrub(value, secrets: [])
        return cleaned == value ? value : ""
    }

    @discardableResult
    public static func save(_ stored: inout [String: String], phase: String, validatedAt: String) -> Bool {
        let phaseSaved = SettingsKeyLedger.save(&stored, activationState, sanitized(phase))
        let validatedSaved = SettingsKeyLedger.save(&stored, lastValidated, sanitized(validatedAt))
        stored.removeValue(forKey: LicenseSecretBoundary.keychainAccount)
        return phaseSaved && validatedSaved
    }

    /// A new map loaded from what `save` kept. This is the recreate step.
    public static func recreate(from stored: [String: String]) -> [String: String] {
        var fresh: [String: String] = [:]
        for item in contributions {
            let loaded = SettingsKeyLedger.load(item, stored: stored[item.id])
            _ = SettingsKeyLedger.save(&fresh, item, sanitized(loaded))
        }
        return fresh
    }
}
