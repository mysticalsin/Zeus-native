import Foundation
import Security

/// Local builds signed with the self-signed "Zeus Local Dev" identity have no Team ID. macOS then
/// pins every file-based Keychain item to that binary. Those older items still live in the
/// `zeus-dev` keychain so a team-signed build can copy them. New provider keys and credentials are
/// not written there. `kSecAttrAccessible` is honoured only by the data protection keychain, so a
/// write sets `kSecUseDataProtectionKeychain` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// and names the team-prefixed access group. A build with no Team ID fails the write and leaves the
/// previous item where it was. Signing and the entitlement have to be shown on a Mac.
public enum DevKeychain {
    public static var path: String { NSHomeDirectory() + "/Library/Keychains/zeus-dev.keychain-db" }
    public static var passwordFiles: [String] {
        [NSHomeDirectory() + "/.zeus/devkeychain.pass", NSHomeDirectory() + "/.zeus-dev/codesign/keychain-pass"]
    }

    /// The signing TeamIdentifier, or nil for an ad hoc or self-signed build and for a failed read.
    public static var teamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// True when this process's signature carries no Team ID (ad hoc or self-signed).
    public static var isLocalBuild: Bool { teamIdentifier == nil }

    /// The opened (and unlocked) dev keychain, or nil when this build should use the login keychain.
    /// Legacy items are read from here. New items go to the data protection keychain.
    nonisolated(unsafe) public static let shared: SecKeychain? = {
        guard ProcessInfo.processInfo.environment["ZEUS_LOGIN_KEYCHAIN"] == nil, isLocalBuild,
              FileManager.default.fileExists(atPath: path),
              let file = passwordFiles.first(where: { FileManager.default.isReadableFile(atPath: $0) }),
              let raw = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        let password = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var keychain: SecKeychain?
        guard SecKeychainOpen(path, &keychain) == errSecSuccess, let keychain else { return nil }
        var status = SecKeychainStatus()
        if SecKeychainGetStatus(keychain, &status) != errSecSuccess || status & UInt32(kSecUnlockStateStatus) == 0 {
            let bytes = Array(password.utf8)
            guard SecKeychainUnlock(keychain, UInt32(bytes.count), bytes, true) == errSecSuccess else { return nil }
        }
        return keychain
    }()
}

/// The Keychain, with user interaction switched off for every call. Provider keys and credentials
/// are written through `CredentialKeychainMigration` into the data protection keychain. Legacy
/// file-based items are read, copied, checked, and only then deleted.
public struct SystemKeychain: KeychainBackend {
    private var dev: SecKeychain? { DevKeychain.shared }
    public init() {}

    /// "zeus-dev" or "login", for reports of where a legacy item would be read. New items are not stored there.
    public var location: String { dev == nil ? "login" : "zeus-dev" }

    private func quietly<T>(_ body: () -> T) -> T {
        var allowed: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&allowed)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return body()
    }

    private func scoped(_ service: String) -> SecKeychain? { service == KeychainStore.service ? dev : nil }

    private func legacyQuery(_ service: String, _ account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { query[kSecAttrAccount as String] = account }
        if let keychain = scoped(service) { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }

    public func accounts(service: String) -> [String] {
        quietly {
            let adapter = SecCredentialKeychain(teamIdentifier: DevKeychain.teamIdentifier ?? "", legacyQuery: { self.legacyQuery($0, $1) })
            var seen = Set<String>()
            var names: [String] = []
            for name in adapter.accounts(service: service, protected: true) + adapter.accounts(service: service, protected: false)
                where seen.insert(name).inserted {
                names.append(name)
            }
            return names
        }
    }

    public func read(service: String, account: String) -> String? {
        quietly {
            guard let team = DevKeychain.teamIdentifier else {
                KeychainSecretStates.shared.set(.needsReentry, service: service, account: account)
                return nil
            }
            let adapter = SecCredentialKeychain(teamIdentifier: team, legacyQuery: { self.legacyQuery($0, $1) })
            let outcome = CredentialKeychainMigration.migrate(service: service, account: account, teamIdentifier: team, keychain: adapter)
            KeychainSecretStates.shared.set(outcome.state, service: service, account: account)
            guard outcome == .migrated || outcome == .alreadyProtected else { return nil }
            guard case .value(let data) = adapter.readProtected(service: service, account: account),
                  let text = String(data: data, encoding: .utf8) else {
                KeychainSecretStates.shared.set(.needsReentry, service: service, account: account)
                return nil
            }
            return text
        }
    }

    public func write(_ value: String, service: String, account: String) -> Bool {
        quietly {
            guard let team = DevKeychain.teamIdentifier else {
                KeychainSecretStates.shared.set(.needsReentry, service: service, account: account)
                return false
            }
            let adapter = SecCredentialKeychain(teamIdentifier: team, legacyQuery: { self.legacyQuery($0, $1) })
            let outcome = CredentialKeychainMigration.write(data: Data(value.utf8), service: service, account: account, teamIdentifier: team, keychain: adapter)
            KeychainSecretStates.shared.set(outcome.state, service: service, account: account)
            return outcome == .migrated
        }
    }

    @discardableResult
    public func delete(service: String, account: String) -> Bool {
        quietly {
            let adapter = SecCredentialKeychain(teamIdentifier: DevKeychain.teamIdentifier ?? "", legacyQuery: { self.legacyQuery($0, $1) })
            if DevKeychain.teamIdentifier != nil, !adapter.deleteProtected(service: service, account: account) { return false }
            return adapter.deleteLegacy(service: service, account: account)
        }
    }
}

/// File-based items and data-protection items. The secret is passed as `Data` and is not interpolated.
private struct SecCredentialKeychain: CredentialKeychain {
    var teamIdentifier: String = ""
    var legacyQuery: (String, String?) -> [String: Any] = { _, _ in [:] }

    func readLegacy(service: String, account: String) -> KeychainRead {
        classify(legacyQuery(service, account))
    }

    func readProtected(service: String, account: String) -> KeychainRead {
        guard let query = protectedQuery(service, account) else { return .unreadable }
        return classify(query)
    }

    func writeProtected(_ data: Data, request: KeychainWriteRequest) -> Bool {
        guard request.useDataProtectionKeychain,
              let access = request.accessibility,
              let group = request.accessGroup,
              group == CredentialKeychainPolicy.accessGroup(teamIdentifier: teamIdentifier),
              var query = protectedQuery(request.service, request.account) else { return false }
        var update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.constant(access),
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "ZEUS"
        query[kSecAttrAccessible as String] = Self.constant(access)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func deleteLegacy(service: String, account: String) -> Bool {
        let status = SecItemDelete(legacyQuery(service, account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func deleteProtected(service: String, account: String) -> Bool {
        guard let query = protectedQuery(service, account) else { return false }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func accounts(service: String, protected: Bool) -> [String] {
        var query: [String: Any]
        if protected {
            guard let base = protectedQuery(service, nil) else { return [] }
            query = base
        } else {
            query = legacyQuery(service, nil)
        }
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func protectedQuery(_ service: String, _ account: String?) -> [String: Any]? {
        guard let group = CredentialKeychainPolicy.accessGroup(teamIdentifier: teamIdentifier) else { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: group,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func classify(_ query: [String: Any]) -> KeychainRead {
        var copy = query
        copy[kSecReturnData as String] = true
        copy[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(copy as CFDictionary, &result)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = result as? Data else { return .unreadable }
        return .value(data)
    }

    private static func constant(_ access: KeychainAccessibility) -> CFString {
        switch access {
        case .whenUnlockedThisDeviceOnly: return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}
