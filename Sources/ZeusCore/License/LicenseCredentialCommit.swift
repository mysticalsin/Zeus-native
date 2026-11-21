import Foundation

/// How a license key and its activation proof are saved, and how a server refusal stays with the key.
/// The Keychain has no transaction, so a failed key write has to undo the proof or the pair is refused.
public enum LicenseCredentialCommit {
    public static let keyAccount = "license.key"
    public static let proofAccount = "license.activation"
    /// Same decision as the defaults flag, stored in the Keychain beside the key.
    public static let refusalAccount = "license.activationRejected"
    /// Covers whatever key is still stored when a partial write cannot be undone.
    public static let blockAll = "*"

    public enum WriteResult: Equatable, Sendable {
        case stored
        case proofNotSaved
        case keyNotSaved
        case blocked
    }

    public struct Refusal: Equatable, Sendable {
        public var recorded: Bool
        public var keyRemoved: Bool
        /// The key is still there and the refusal could not be stored next to it.
        public var needsCleanup: Bool
    }

    /// `write` takes the secret value, then the account name.
    /// `proof` nil leaves the saved proof alone (an offline activation has none yet).
    /// A failed key write restores `previousProof`. If that undo also fails, the refusal
    /// marker blocks whatever key is still stored.
    public static func store(key: String, proof: String?, previousProof: String?,
                              write: (String, String) -> Bool, delete: (String) -> Bool) -> WriteResult {
        if let proof {
            guard write(proof, proofAccount) else { return .proofNotSaved }
        }
        if write(key, keyAccount) { return .stored }
        guard proof != nil else { return .keyNotSaved }
        let restored = previousProof.map { write($0, proofAccount) } ?? delete(proofAccount)
        if restored { return .keyNotSaved }
        _ = write(blockAll, refusalAccount)
        return .blocked
    }

    /// Record `licenseID` beside the key, then try to remove the key.
    public static func refuse(licenseID: String, write: (String, String) -> Bool, deleteKey: () -> Bool) -> Refusal {
        let recorded = write(licenseID, refusalAccount)
        let keyRemoved = deleteKey()
        return Refusal(recorded: recorded, keyRemoved: keyRemoved, needsCleanup: !recorded && !keyRemoved)
    }

    /// True when this key must not license. A missing key is not covered.
    /// `blockAll` covers every stored key. Any other marker covers only that license id.
    public static func covers(refusal: String?, licenseID: String?, hasKey: Bool) -> Bool {
        guard hasKey, let refusal, !refusal.isEmpty else { return false }
        if refusal == blockAll { return true }
        guard let licenseID, !licenseID.isEmpty else { return false }
        return refusal == licenseID
    }
}
