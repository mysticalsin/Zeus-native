import Foundation

public protocol CredentialStore: Sendable {
    func read(service: String, account: String) -> String?
    func write(_ value: String, service: String, account: String) -> Bool
    /// Deletes every account under `service`. Do not use this for `com.zeus.app`.
    func delete(service: String) -> Bool
    func delete(service: String, account: String) -> Bool
}

public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    public init() {}

    public func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[key(service, account)]
    }

    public func write(_ value: String, service: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        items[key(service, account)] = value
        return true
    }

    public func delete(service: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let prefix = service + "|"
        for name in items.keys where name.hasPrefix(prefix) { items[name] = nil }
        return true
    }

    public func delete(service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[key(service, account)] = nil
        return true
    }

    private func key(_ service: String, _ account: String) -> String { "\(service)|\(account)" }
}

#if os(macOS)
import Security

/// Generic-password items, one service per provider, readable when this device is unlocked.
/// User interaction is off, so a locked item comes back missing instead of raising a dialog.
public struct KeychainCredentialStore: CredentialStore, Sendable {
    public init() {}

    public func read(service: String, account: String) -> String? {
        SystemKeychain().read(service: service, account: account)
    }

    public func write(_ value: String, service: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        return quietly {
            let data = Data(value.utf8)
            let update = [kSecValueData as String: data]
            let status = SecItemUpdate(base(service, account) as CFDictionary, update as CFDictionary)
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            var add = base(service, account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            add[kSecAttrLabel as String] = "ZEUS voice provider"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }

    public func delete(service: String) -> Bool {
        let status = quietly { SecItemDelete(base(service, nil) as CFDictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func delete(service: String, account: String) -> Bool {
        let status = quietly { SecItemDelete(base(service, account) as CFDictionary) }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func base(_ service: String, _ account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func quietly<T>(_ body: () -> T) -> T {
        var allowed: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&allowed)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
        return body()
    }
}
#endif
