import Foundation

/// What a saved revocation list means when it cannot be read.
/// A decoded list is the authority. A missing or undecodable list must not clear a revocation already recorded.
public enum LicenseRevocationPolicy {
    public static let defaultsKey = "license.revokedIDs"
    public static let keychainAccount = "license.revokedIDs"

    /// `decodedIDs` nil means the signed list is missing or did not verify.
    /// That result is unknown: a key already on the last good list stays revoked, and a key with no record does not.
    public static func isRevoked(id: String, decodedIDs: [String]?, lastGoodIDs: [String]) -> Bool {
        if let decodedIDs { return decodedIDs.contains(id) }
        return lastGoodIDs.contains(id)
    }

    /// The defaults cache and the Keychain copy are both unsigned. A revocation kept in either one
    /// stays until a signed list says otherwise. A missing defaults key uses the Keychain copy alone.
    public static func load(defaultsIDs: [String]?, keychainText: String?) -> [String] {
        let stored = keychainText?.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
        guard let defaultsIDs else { return stored }
        return Array(Set(defaultsIDs).union(stored)).sorted()
    }

    public static func keychainText(ids: [String]) -> String {
        ids.joined(separator: "\n")
    }
}
