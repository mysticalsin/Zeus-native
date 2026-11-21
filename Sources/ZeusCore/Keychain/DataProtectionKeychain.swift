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
    func writeProtected(_ data: Data, request: KeychainWriteRequest) -> Bool
    func deleteLegacy(service: String, account: String) -> Bool
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
/// group is the signing TeamIdentifier, a dot, and `app.zeus.mac` — the same team prefix codesign
/// reports, written in the entitlement as `$(AppIdentifierPrefix)`.
///
/// No account is readable while the screen is locked. Launch at login runs after the person unlocks,
/// and the warm-up timer reads the copy already in memory. `whileLockedAccounts` is empty. An item
/// may use `afterFirstUnlockThisDeviceOnly` only by being named there.
public enum CredentialKeychainPolicy {
    public static let accessGroupSuffix = "app.zeus.mac"
    public static let entitlementKey = "keychain-access-groups"
    public static let entitlementGroup = "$(AppIdentifierPrefix)app.zeus.mac"
    /// Accounts a scheduled or background job must read while the screen is locked. None.
    public static let whileLockedAccounts: Set<String> = []

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

/// Copies a legacy item into the data protection keychain, or writes a new value there.
/// Order for a copy: read the legacy item, write the protected item, read it back, and only then
/// delete the legacy item. A failed write or a read-back that does not match leaves the legacy item
/// in place. There is no other store.
public enum CredentialKeychainMigration {
    public static func logLine(account: String, outcome: CredentialMigrationOutcome) -> String {
        "keychain account=\(account) outcome=\(outcome.logName)"
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
