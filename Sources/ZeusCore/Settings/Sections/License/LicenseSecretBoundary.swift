import Foundation

/// The license key stays in the existing Keychain item. It is not a catalog setting and it is not exported.
public enum LicenseSecretBoundary {
    public static let keychainAccount = "license.key"

    /// Keychain accounts. None of these are settings.
    public static let secretIDs: Set<String> = [keychainAccount, "license.activation", "trial.start", "license.server.origin"]

    public static func holdsSecretID(_ id: String) -> Bool { secretIDs.contains(id) }

    /// Drops secret ids and any value that still contains a license key.
    public static func exportable(_ values: [String: String]) -> [String: String] {
        values.filter { id, value in
            guard !holdsSecretID(id) else { return false }
            return LicenseKeyPrivacy.scrub(value, secrets: []) == value
        }
    }
}
