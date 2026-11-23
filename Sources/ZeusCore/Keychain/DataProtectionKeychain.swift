import Foundation

/// How a provider key or credential may be read back. On macOS only the data protection keychain
/// honours this. `whenUnlockedThisDeviceOnly` keeps the item unavailable while the screen is locked
/// and stops it moving to another Mac. `afterFirstUnlockThisDeviceOnly` is the one exception, and
/// only for an account named in `CredentialKeychainPolicy.whileLockedAccounts`.
public enum KeychainAccessibility: Equatable, Sendable {
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlockThisDeviceOnly
}

/// One field of a Keychain write. The bytes of a secret are never one of these fields.
public enum KeychainAttribute: Equatable, Sendable {
    case useDataProtectionKeychain(Bool)
    case accessible(KeychainAccessibility)
    case accessGroup(String)
    case service(String)
    case account(String)
}

/// The attributes a protected write must carry. Tests record this value. No Keychain call is made here.
public struct KeychainWriteRequest: Equatable, Sendable {
    public var service: String
    public var account: String
    public var attributes: [KeychainAttribute]

    public var useDataProtectionKeychain: Bool {
        for case .useDataProtectionKeychain(let on) in attributes { return on }
        return false
    }

    public var accessibility: KeychainAccessibility? {
        for case .accessible(let value) in attributes { return value }
        return nil
    }

    public var accessGroup: String? {
        for case .accessGroup(let group) in attributes { return group }
        return nil
    }

    /// The class copied onto an item that already exists, so a planted class does not remain.
    public var updateAttributes: [KeychainAttribute] {
        attributes.filter { if case .accessible = $0 { return true } else { return false } }
    }
}

/// What a read found. `unreadable` means the item is there but a prompt or a locked screen blocks it.
public enum KeychainRead: Equatable, Sendable {
    case value(Data)
    case absent
    case unreadable
}

/// The store the migration talks to. A test records every call. The macOS Keychain is the other adopter.
public protocol CredentialKeychain: Sendable {
    func readLegacy(service: String, account: String) -> KeychainRead
    func readProtected(service: String, account: String) -> KeychainRead
    /// Label, creator and whether the access list admits every program. Never the secret.
    func legacyFacts(service: String, account: String) -> LegacyItemFacts
    /// Every legacy match, each with its own persistent reference. Not limited to one.
    func legacyCandidates(service: String, account: String) -> [LegacyCandidate]
    func writeProtected(_ data: Data, request: KeychainWriteRequest) -> Bool
    func writeLegacy(_ data: Data, service: String, account: String) -> Bool
    /// Replaces one legacy item, then the caller reads that same reference back.
    func updateLegacyItem(_ data: Data, persistentRef: Data) -> Bool
    func deleteLegacy(service: String, account: String) -> Bool
    /// Deletes one legacy item. Other matches for the same account stay.
    func deleteLegacyItem(persistentRef: Data) -> Bool
    func deleteProtected(service: String, account: String) -> Bool
}

/// Words the app can show. `needsReentry` is the state "This key needs re-entry".
public enum KeychainSecretState: Equatable, Sendable {
    case available
    case missing
    case needsReentry
    case locked

    public var title: String {
        switch self {
        case .available: return "Saved on this Mac"
        case .missing: return "No key on this Mac"
        case .needsReentry: return "This key needs re-entry"
        case .locked: return "Unlock this Mac to use this key"
        }
    }

    public var detail: String {
        switch self {
        case .available:
            return "This key is locked while the screen is locked, and it does not move to another Mac."
        case .missing:
            return "No key is stored on this Mac. A key entered on another Mac does not move here."
        case .needsReentry:
            return "Zeus could not lock the previous copy to this Mac, so it was left in place. This key needs re-entry."
        case .locked:
            return "The key stays where it is until this Mac is unlocked."
        }
    }
}

/// The last state recorded for an account. The secret itself is never stored here.
public final class KeychainSecretStates: @unchecked Sendable {
    public static let shared = KeychainSecretStates()
    private let lock = NSLock()
    private var values: [String: KeychainSecretState] = [:]

    public func set(_ state: KeychainSecretState, service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        values["\(service)|\(account)"] = state
    }

    public func state(service: String, account: String) -> KeychainSecretState {
        lock.lock(); defer { lock.unlock() }
        return values["\(service)|\(account)"] ?? .missing
    }
}

/// Rules for every provider key and credential write. The providers branch names this role
/// `CredentialStore`. On this tree the only SecItem writer is `SystemKeychain`, and it calls
/// `CredentialKeychainMigration` for each of those writes.
///
/// `kSecAttrAccessible` is honoured only by the data protection keychain, so a write sets
/// `kSecUseDataProtectionKeychain` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The access
/// group is the signing TeamIdentifier, a dot, and `app.zeus.mac`, the same team prefix codesign
/// reports. The entitlement file still contains `$(AppIdentifierPrefix)`, which a non-Xcode
/// signature does not expand, so that build fails closed.
///
/// No account is readable while the screen is locked. Launch at login runs after the person unlocks,
/// and the warm-up timer reads the copy already in memory. `whileLockedAccounts` is empty. An item
/// may use `afterFirstUnlockThisDeviceOnly` only by being named there.
public enum CredentialKeychainPolicy {
    public static let accessGroupSuffix = "app.zeus.mac"
    public static let entitlementKey = "keychain-access-groups"
    /// One group suffix. Callers add the team prefix from the signed binary.
    public static let accessGroup = accessGroupSuffix
    public static let entitlementGroup = "$(AppIdentifierPrefix)" + accessGroupSuffix
    public static let zeusLabel = "ZEUS"
    public static let zeusCreator = "ZEUS"
    /// Present means on. Never copy a legacy item into this account.
    public static let cliSwitchAccount = "cli.control.enabled"
    public static let vaultKeyAccount = "face.presence.vaultKey"
    /// Downgrade copy-back must never write these. User removal deletes them instead.
    public static let neverCopyBack: Set<String> = [cliSwitchAccount, vaultKeyAccount]
    public static let bundleIdentifier = "app.zeus.mac"
    /// Accounts a scheduled or background job must read while the screen is locked. None.
    public static let whileLockedAccounts: Set<String> = []
    /// Account names Zeus itself creates. A credential origin (suffix `.origin`) is never in this set.
    public static let importableAccounts: Set<String> = [
        "elevenlabs.api-key", "elevenlabs.voice-id", "license.key", "license.activation", "trial.start",
        "assistant.key.openAI", "assistant.key.anthropic", "assistant.key.elevenLabs", "assistant.key.openai",
        "worker.url", "worker.token", "cloud.key.openai", "cloud.key.anthropic", "cloud.key.elevenlabs",
        "cloudflare.api-token", "jev-api-key", "anyllm-api-key", "openai-tts.api-key", "gemini-tts.api-key",
        "chatterbox.api-key", "face.presence.vaultKey", "insomnia.hotspotPassword",
    ]

    /// Label and creator are not provenance. An open list, or any list other than Zeus alone, is not Zeus.
    public static func zeusWrote(_ facts: LegacyItemFacts) -> Bool {
        if facts.anyProgram { return false }
        return facts.creator == zeusCreator || facts.label == zeusLabel
    }

    /// Team id plus bundle id, the designated requirement an imported item's access list must name.
    public static func designatedRequirement(teamIdentifier: String) -> String? {
        guard isTeamIdentifier(teamIdentifier) else { return nil }
        return "identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// True when the trusted-app list is exactly Zeus's designated requirement and nobody else.
    public static func aclIsOnlyZeus(_ facts: LegacyItemFacts, teamIdentifier: String) -> Bool {
        guard !facts.anyProgram, let expected = designatedRequirement(teamIdentifier: teamIdentifier) else { return false }
        return facts.trustedRequirements == [expected]
    }

    /// True for an account Zeus creates. The command-line switch and every `*.origin` account are refused.
    public static func mayImport(account: String) -> Bool {
        if account == cliSwitchAccount || account.hasSuffix(".origin") { return false }
        if importableAccounts.contains(account) { return true }
        let prefix = "fling.peer."
        guard account.hasPrefix(prefix) else { return false }
        let rest = account.dropFirst(prefix.count)
        return !rest.isEmpty && rest.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    public static func isTeamIdentifier(_ team: String) -> Bool {
        team.range(of: #"^[A-Z0-9]+$"#, options: .regularExpression) != nil
    }

    public static func accessGroup(teamIdentifier: String) -> String? {
        guard isTeamIdentifier(teamIdentifier) else { return nil }
        return teamIdentifier + "." + accessGroupSuffix
    }

    public static func accessibility(account: String, whileLocked: Set<String> = whileLockedAccounts) -> KeychainAccessibility {
        whileLocked.contains(account) ? .afterFirstUnlockThisDeviceOnly : .whenUnlockedThisDeviceOnly
    }

    public static func writeRequest(service: String, account: String, teamIdentifier: String) -> KeychainWriteRequest? {
        guard let group = accessGroup(teamIdentifier: teamIdentifier) else { return nil }
        return KeychainWriteRequest(service: service, account: account, attributes: [
            .useDataProtectionKeychain(true),
            .accessible(accessibility(account: account)),
            .accessGroup(group),
            .service(service),
            .account(account),
        ])
    }
}

/// Result of moving one item into the data protection keychain. The secret is not part of the result
/// and must not be logged. `logLine` names the account and the outcome only.
public enum CredentialMigrationOutcome: Equatable, Sendable {
    case migrated
    case alreadyProtected
    case absent
    case locked
    case needsReentry

    public var state: KeychainSecretState {
        switch self {
        case .migrated, .alreadyProtected: return .available
        case .absent: return .missing
        case .locked: return .locked
        case .needsReentry: return .needsReentry
        }
    }

    public var logName: String {
        switch self {
        case .migrated: return "migrated"
        case .alreadyProtected: return "alreadyProtected"
        case .absent: return "absent"
        case .locked: return "locked"
        case .needsReentry: return "needsReentry"
        }
    }
}

/// Attributes of a legacy item. The secret is not one of them.
public struct LegacyItemFacts: Equatable, Sendable {
    public var label: String
    public var creator: String
    public var anyProgram: Bool
    /// Code requirements of the trusted applications. One entry, equal to Zeus's designated requirement, is required to import.
    public var trustedRequirements: [String]
    public init(label: String, creator: String, anyProgram: Bool, trustedRequirements: [String] = []) {
        self.label = label
        self.creator = creator
        self.anyProgram = anyProgram
        self.trustedRequirements = trustedRequirements
    }
    public static let zeus = LegacyItemFacts(label: CredentialKeychainPolicy.zeusLabel,
                                              creator: CredentialKeychainPolicy.zeusCreator,
                                              anyProgram: false)
}

/// One legacy match. `persistentRef` identifies that item alone. It is not the secret.
public struct LegacyCandidate: Equatable, Sendable {
    public var persistentRef: Data
    public var data: Data
    public var facts: LegacyItemFacts
}

/// One pass over a legacy item. `markMigrated` is what the caller persists so the pass does not run again.
public struct MigrationAttempt: Equatable, Sendable {
    public var outcome: CredentialMigrationOutcome
    public var markMigrated: Bool
}

/// Accounts whose legacy item has already been considered. The secret is not stored here.
public final class MigrationFlagStore: @unchecked Sendable {
    public static let key = "keychain.dp.migrated.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func contains(service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (defaults.stringArray(forKey: Self.key) ?? []).contains(Self.id(service, account))
    }

    public func mark(service: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        var items = defaults.stringArray(forKey: Self.key) ?? []
        let id = Self.id(service, account)
        guard !items.contains(id) else { return }
        items.append(id)
        defaults.set(items, forKey: Self.key)
    }

    private static func id(_ service: String, _ account: String) -> String { "\(service)|\(account)" }
}

/// Copies a legacy item into the data protection keychain, or writes a new value there.
/// Order for a copy: read the legacy item, write the protected item, read it back, and only then
/// delete the legacy item. A failed write or a read-back that does not match leaves the legacy item
/// in place. There is no other store.
public enum CredentialKeychainMigration {
    public static func logLine(account: String, outcome: CredentialMigrationOutcome) -> String {
        "keychain account=\(account) outcome=\(outcome.logName)"
    }

    /// Considers each legacy item once. The command-line switch is never copied. A foreign item is ignored.
    /// A missing team id, which is what a missing group entitlement produces here, writes nothing and does not
    /// record the flag.
    public static func migrateOnce(service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain, alreadyMigrated: Bool) -> MigrationAttempt {
        guard CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier) != nil else {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
        }
        if alreadyMigrated || account == CredentialKeychainPolicy.cliSwitchAccount {
            return MigrationAttempt(outcome: protectedOnly(service: service, account: account, keychain: keychain), markMigrated: true)
        }
        guard CredentialKeychainPolicy.mayImport(account: account) else {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: true)
        }
        return importEligible(service: service, account: account, teamIdentifier: teamIdentifier, keychain: keychain)
    }

    /// User removal. Deletes every legacy match first, then the protected item. Does not write a copy back.
    /// A failed legacy delete leaves the protected item in place, so the login item is not left on its own.
    public static func removeEverywhere(service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> MigrationAttempt {
        guard CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier) != nil else {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
        }
        guard keychain.deleteLegacy(service: service, account: account),
              keychain.deleteProtected(service: service, account: account) else {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
        }
        return MigrationAttempt(outcome: .absent, markMigrated: true)
    }

    /// Explicit downgrade only. Never for the command-line switch or the face vault key.
    /// Updates an existing item only when its access list is Zeus alone, then reads that item back.
    public static func copyBackForDowngrade(service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> MigrationAttempt {
        guard CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier) != nil else {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
        }
        if CredentialKeychainPolicy.neverCopyBack.contains(account) {
            return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
        }
        switch keychain.readProtected(service: service, account: account) {
        case .unreadable:
            return MigrationAttempt(outcome: .locked, markMigrated: false)
        case .absent:
            return MigrationAttempt(outcome: .absent, markMigrated: true)
        case .value(let data):
            let candidates = keychain.legacyCandidates(service: service, account: account)
            if let target = candidates.first(where: { CredentialKeychainPolicy.aclIsOnlyZeus($0.facts, teamIdentifier: teamIdentifier) }) {
                guard keychain.updateLegacyItem(data, persistentRef: target.persistentRef) else {
                    return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
                }
                let after = keychain.legacyCandidates(service: service, account: account)
                guard let found = after.first(where: { $0.persistentRef == target.persistentRef }), found.data == data,
                      keychain.deleteProtected(service: service, account: account) else {
                    return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
                }
                return MigrationAttempt(outcome: .migrated, markMigrated: true)
            }
            if !candidates.isEmpty {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
            }
            guard keychain.writeLegacy(data, service: service, account: account) else {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
            }
            let after = keychain.legacyCandidates(service: service, account: account)
            guard after.contains(where: { $0.data == data }),
                  keychain.deleteProtected(service: service, account: account) else {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
            }
            return MigrationAttempt(outcome: .migrated, markMigrated: true)
        }
    }

    public static func migrate(service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> CredentialMigrationOutcome {
        guard CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier) != nil else {
            return .needsReentry
        }
        switch keychain.readLegacy(service: service, account: account) {
        case .unreadable:
            return existing(service: service, account: account, keychain: keychain, ifAbsent: .locked)
        case .absent:
            return existing(service: service, account: account, keychain: keychain, ifAbsent: .absent)
        case .value(let data):
            switch keychain.readProtected(service: service, account: account) {
            case .value(let stored):
                guard stored == data else { return .needsReentry }
                return verify(stored, service: service, account: account, keychain: keychain, success: .alreadyProtected)
            case .unreadable:
                return .locked
            case .absent:
                guard let request = CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier),
                      keychain.writeProtected(data, request: request) else { return .needsReentry }
                return verify(data, service: service, account: account, keychain: keychain, success: .migrated)
            }
        }
    }

    /// Saves a new value. The legacy item is deleted only after the protected item reads back the same bytes.
    public static func write(data: Data, service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> CredentialMigrationOutcome {
        guard let request = CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier),
              keychain.writeProtected(data, request: request) else { return .needsReentry }
        return verify(data, service: service, account: account, keychain: keychain, success: .migrated)
    }

    /// Copies the first legacy item whose access list is only Zeus. Every other match is kept.
    /// Running again does not overwrite a different protected value and does not delete a non-matching item.
    private static func importEligible(service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> MigrationAttempt {
        let candidates = keychain.legacyCandidates(service: service, account: account)
        switch keychain.readProtected(service: service, account: account) {
        case .unreadable:
            return MigrationAttempt(outcome: .locked, markMigrated: false)
        case .value(let existing):
            for candidate in candidates where candidate.data == existing && CredentialKeychainPolicy.aclIsOnlyZeus(candidate.facts, teamIdentifier: teamIdentifier) {
                _ = keychain.deleteLegacyItem(persistentRef: candidate.persistentRef)
            }
            return MigrationAttempt(outcome: .alreadyProtected, markMigrated: true)
        case .absent:
            guard let chosen = candidates.first(where: { CredentialKeychainPolicy.aclIsOnlyZeus($0.facts, teamIdentifier: teamIdentifier) }) else {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: true)
            }
            guard let request = CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier),
                  keychain.writeProtected(chosen.data, request: request),
                  case .value(let back) = keychain.readProtected(service: service, account: account), back == chosen.data,
                  keychain.deleteLegacyItem(persistentRef: chosen.persistentRef) else {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
            }
            return MigrationAttempt(outcome: .migrated, markMigrated: true)
        }
    }

    private static func protectedOnly(service: String, account: String, keychain: any CredentialKeychain) -> CredentialMigrationOutcome {
        switch keychain.readProtected(service: service, account: account) {
        case .value: return .alreadyProtected
        case .absent: return .absent
        case .unreadable: return .locked
        }
    }

    private static func importOwned(_ data: Data, service: String, account: String, teamIdentifier: String, keychain: any CredentialKeychain) -> MigrationAttempt {
        switch keychain.readProtected(service: service, account: account) {
        case .value(let stored):
            guard stored == data else { return MigrationAttempt(outcome: .needsReentry, markMigrated: true) }
            let outcome = verify(stored, service: service, account: account, keychain: keychain, success: .alreadyProtected)
            return MigrationAttempt(outcome: outcome, markMigrated: outcome == .alreadyProtected)
        case .unreadable:
            return MigrationAttempt(outcome: .locked, markMigrated: false)
        case .absent:
            guard let request = CredentialKeychainPolicy.writeRequest(service: service, account: account, teamIdentifier: teamIdentifier),
                  keychain.writeProtected(data, request: request) else {
                return MigrationAttempt(outcome: .needsReentry, markMigrated: false)
            }
            let outcome = verify(data, service: service, account: account, keychain: keychain, success: .migrated)
            return MigrationAttempt(outcome: outcome, markMigrated: outcome == .migrated)
        }
    }

    private static func existing(service: String, account: String, keychain: any CredentialKeychain, ifAbsent: CredentialMigrationOutcome) -> CredentialMigrationOutcome {
        switch keychain.readProtected(service: service, account: account) {
        case .absent: return ifAbsent
        case .unreadable: return .locked
        case .value(let stored):
            return verify(stored, service: service, account: account, keychain: keychain, success: .alreadyProtected)
        }
    }

    private static func verify(_ expected: Data, service: String, account: String, keychain: any CredentialKeychain, success: CredentialMigrationOutcome) -> CredentialMigrationOutcome {
        guard case .value(let back) = keychain.readProtected(service: service, account: account), back == expected else {
            return .needsReentry
        }
        guard keychain.deleteLegacy(service: service, account: account) else { return .needsReentry }
        return success
    }
}
