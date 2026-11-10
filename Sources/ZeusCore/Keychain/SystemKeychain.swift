import Foundation
import Security

/// Local builds signed with the self-signed "Zeus Local Dev" identity have no Team ID, and macOS
/// then pins every Keychain item an app creates to that exact binary (partition `cdhash:`), so a
/// rebuild silently loses its own secrets even with a stable designated requirement. For those
/// builds only, `com.zeus.app` lives in the dedicated `zeus-dev` keychain, whose password sits in a
/// mode-600 file outside the repo; `scripts/bundle.sh` adds each new build's cdhash to the items'
/// partition list with that password, so no dialog ever appears. Team-signed (Developer ID)
/// builds get a stable `teamid:` partition and keep using the login keychain.
public enum DevKeychain {
    public static var path: String { NSHomeDirectory() + "/Library/Keychains/zeus-dev.keychain-db" }
    public static var passwordFiles: [String] {
        [NSHomeDirectory() + "/.zeus/devkeychain.pass", NSHomeDirectory() + "/.zeus-dev/codesign/keychain-pass"]
    }

    /// True when this process's signature carries no Team ID (ad hoc or self-signed).
    public static var isLocalBuild: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return true }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return true }
        return dict[kSecCodeInfoTeamIdentifier as String] == nil
    }

    /// The opened (and unlocked) dev keychain, or nil when this build should use the login keychain.
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

/// The Keychain, with user interaction switched off for every call. `com.zeus.app` uses the
/// dev keychain on local builds (see `DevKeychain`), the login keychain otherwise.
public struct SystemKeychain: KeychainBackend {
    private var dev: SecKeychain? { DevKeychain.shared }
    public init() {}

    /// "zeus-dev" or "login", for reports.
    public var location: String { dev == nil ? "login" : "zeus-dev" }

    private func quietly<T>(_ body: () -> T) -> T {
        var allowed: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&allowed)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return body()
    }

    private func scoped(_ service: String) -> SecKeychain? { service == KeychainStore.service ? dev : nil }

    private func base(_ service: String, _ account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account { query[kSecAttrAccount as String] = account }
        if let keychain = scoped(service) { query[kSecMatchSearchList as String] = [keychain] }
        return query
    }

    public func accounts(service: String) -> [String] {
        quietly {
            var query = base(service)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let items = result as? [[String: Any]] else { return [] }
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        }
    }

    public func read(service: String, account: String) -> String? {
        quietly {
            var query = base(service, account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    public func write(_ value: String, service: String, account: String) -> Bool {
        quietly {
            let data = Data(value.utf8)
            let update = [kSecValueData as String: data]
            let status = SecItemUpdate(base(service, account) as CFDictionary, update as CFDictionary)
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecAttrAccount as String: account]
            if let keychain = scoped(service) { add[kSecUseKeychain as String] = keychain }
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "ZEUS"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }

    @discardableResult
    public func delete(service: String, account: String) -> Bool {
        let status = quietly { SecItemDelete(base(service, account) as CFDictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

