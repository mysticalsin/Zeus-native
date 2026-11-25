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

enum KeychainStatus {
    static let success: Int32 = 0
    static let notFound: Int32 = -25300
}

struct KeychainCopy: Equatable, Sendable {
    var status: Int32
    var value: String?
    var accessible: String?
}

/// Field names the store sends to the keychain client. The macOS client maps `accessible`
/// to `kSecAttrAccessible` / `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
enum KeychainItemFields {
    static let accessible = "accessible"
    static let whenUnlockedThisDeviceOnly = "when-unlocked-this-device-only"
    static let value = "value-data"
    static let label = "label"
    static let labelText = "ZEUS voice provider"
    static let service = "service"
    static let account = "account"
    static let itemClass = "class"
    static let genericPassword = "generic-password"

    static func update(value: String) -> [String: String] {
        [
            self.value: value,
            accessible: whenUnlockedThisDeviceOnly,
        ]
    }

    static func add(service: String, account: String, value: String) -> [String: String] {
        [
            itemClass: genericPassword,
            self.service: service,
            self.account: account,
            self.value: value,
            accessible: whenUnlockedThisDeviceOnly,
            label: labelText,
        ]
    }
}

protocol KeychainClient: Sendable {
    func copy(service: String, account: String) -> KeychainCopy
    func update(service: String, account: String, attributes: [String: String]) -> Int32
    func add(_ attributes: [String: String]) -> Int32
    func delete(service: String, account: String?) -> Int32
}

/// Generic-password items, readable when this device is unlocked.
/// User interaction is off, so a locked item comes back missing instead of raising a dialog.
/// The first read of an older item migrates it to this-device-only accessibility.
public struct KeychainCredentialStore: CredentialStore, Sendable {
    private let client: any KeychainClient

    public init() {
        #if os(macOS)
        self.client = SecurityKeychainClient()
        #else
        self.client = DisabledKeychainClient()
        #endif
    }

    init(client: any KeychainClient) {
        self.client = client
    }

    public func read(service: String, account: String) -> String? {
        let copied = client.copy(service: service, account: account)
        guard copied.status == KeychainStatus.success, let value = copied.value else { return nil }
        if copied.accessible != KeychainItemFields.whenUnlockedThisDeviceOnly {
            _ = client.update(service: service, account: account, attributes: KeychainItemFields.update(value: value))
        }
        return value
    }

    public func write(_ value: String, service: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        let status = client.update(service: service, account: account, attributes: KeychainItemFields.update(value: value))
        if status == KeychainStatus.success { return true }
        guard status == KeychainStatus.notFound else { return false }
        return client.add(KeychainItemFields.add(service: service, account: account, value: value)) == KeychainStatus.success
    }

    public func delete(service: String) -> Bool {
        let status = client.delete(service: service, account: nil)
        return status == KeychainStatus.success || status == KeychainStatus.notFound
    }

    public func delete(service: String, account: String) -> Bool {
        let status = client.delete(service: service, account: account)
        return status == KeychainStatus.success || status == KeychainStatus.notFound
    }
}

private struct DisabledKeychainClient: KeychainClient {
    func copy(service: String, account: String) -> KeychainCopy {
        KeychainCopy(status: KeychainStatus.notFound, value: nil, accessible: nil)
    }

    func update(service: String, account: String, attributes: [String: String]) -> Int32 {
        KeychainStatus.notFound
    }

    func add(_ attributes: [String: String]) -> Int32 { KeychainStatus.notFound }

    func delete(service: String, account: String?) -> Int32 { KeychainStatus.notFound }
}

#if os(macOS)
import Security

private struct SecurityKeychainClient: KeychainClient {
    func copy(service: String, account: String) -> KeychainCopy {
        quietly {
            var query = securityQuery(service: service, account: account)
            query[kSecReturnData as String] = true
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            let matched = ProviderKeychainMatch.copyItem(query)
            let status = matched.status
            guard status == errSecSuccess else {
                return KeychainCopy(status: status, value: nil, accessible: nil)
            }
            guard let dict = matched.result as? [String: Any] else {
                let data = matched.result as? Data
                return KeychainCopy(status: status, value: data.flatMap { String(data: $0, encoding: .utf8) }, accessible: nil)
            }
            let data = dict[kSecValueData as String] as? Data
            let value = data.flatMap { String(data: $0, encoding: .utf8) }
            let raw = dict[kSecAttrAccessible as String] as? String
            let accessible = raw == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                ? KeychainItemFields.whenUnlockedThisDeviceOnly
                : nil
            return KeychainCopy(status: status, value: value, accessible: accessible)
        }
    }

    func update(service: String, account: String, attributes: [String: String]) -> Int32 {
        quietly {
            SecItemUpdate(
                securityQuery(service: service, account: account) as CFDictionary,
                securityAttributes(attributes) as CFDictionary
            )
        }
    }

    func add(_ attributes: [String: String]) -> Int32 {
        quietly { SecItemAdd(securityAttributes(attributes) as CFDictionary, nil) }
    }

    func delete(service: String, account: String?) -> Int32 {
        quietly { SecItemDelete(securityQuery(service: service, account: account) as CFDictionary) }
    }

    private func securityQuery(service: String, account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func securityAttributes(_ fields: [String: String]) -> [String: Any] {
        var query: [String: Any] = [:]
        for (key, value) in fields {
            switch key {
            case KeychainItemFields.accessible:
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case KeychainItemFields.value:
                query[kSecValueData as String] = Data(value.utf8)
            case KeychainItemFields.label:
                query[kSecAttrLabel as String] = value
            case KeychainItemFields.service:
                query[kSecAttrService as String] = value
            case KeychainItemFields.account:
                query[kSecAttrAccount as String] = value
            case KeychainItemFields.itemClass:
                query[kSecClass as String] = kSecClassGenericPassword
            default:
                continue
            }
        }
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
