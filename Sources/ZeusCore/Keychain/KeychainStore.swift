import Foundation

/// Where secrets physically live. The real one is the macOS Keychain; tests use memory.
public protocol KeychainBackend: Sendable {
    /// Every account under `service` (attributes only, no secrets).
    func accounts(service: String) -> [String]
    /// The value, or nil when missing or when reading would need the person to click a dialog.
    func read(service: String, account: String) -> String?
    @discardableResult func write(_ value: String, service: String, account: String) -> Bool
    @discardableResult func delete(service: String, account: String) -> Bool
}

/// ZEUS's single Keychain home: one service, `com.zeus.app`, read once at launch and kept in
/// memory, so the app never asks the Keychain twice and never raises a password dialog.
///
/// Why there are no prompts: every read runs with user interaction turned off (a locked or
/// foreign-ACL item comes back as missing instead of a dialog), items are created by the app
/// itself (so the app's code signature is on their access list), and the app is signed with
/// one stable identity (`scripts/make-dev-identity.sh`). Local builds keep the items in the
/// `zeus-dev` keychain so rebuilds keep that access (see `DevKeychain`).
///
/// Merge note: devon/claude and devon/cli should read and write through this type (or the same
/// service and account names) instead of their own services.
public final class KeychainStore: @unchecked Sendable {
    public static let service = "com.zeus.app"

    /// Old services and accounts, copied once into `com.zeus.app` and then never read again.
    public static let legacy: [(service: String, account: String, to: String)] = [
        ("com.zeus.elevenlabs", "api-key", "elevenlabs.api-key"),
        ("com.zeus.elevenlabs", "voice-id", "elevenlabs.voice-id"),
        ("ai.zeus.app", "license.key", "license.key"),
        ("ai.zeus.app", "trial.start", "trial.start"),
        ("ai.zeus.app", "assistant.key.openAI", "assistant.key.openAI"),
        ("ai.zeus.app", "assistant.key.anthropic", "assistant.key.anthropic"),
        ("ai.zeus.app", "assistant.key.elevenLabs", "assistant.key.elevenLabs"),
        ("com.zeus.worker", "url", "worker.url"),
        ("com.zeus.worker", "token", "worker.token"),
        ("com.zeus.keys", "openai", "cloud.key.openai"),
        ("com.zeus.keys", "anthropic", "cloud.key.anthropic"),
        ("com.zeus.keys", "elevenlabs", "cloud.key.elevenlabs"),
        ("com.zeus.cloudflare", "api-token", "cloudflare.api-token"),
    ]
    static let migratedFlag = "keychain.migrated.v1"
    static let unreadableKey = "keychain.legacy.unreadable"

    private let backend: KeychainBackend
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var loaded = false
    private let defaults: UserDefaults
    /// Legacy items that exist but could not be read without a dialog.
    public private(set) var unreadableLegacy: [String] = []

    public init(backend: KeychainBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    /// Reads everything once (and migrates once). Safe to call again; later calls do nothing.
    public func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        for account in backend.accounts(service: Self.service) {
            if let value = backend.read(service: Self.service, account: account) { cache[account] = value }
        }
        guard !defaults.bool(forKey: Self.migratedFlag) else {
            unreadableLegacy = defaults.stringArray(forKey: Self.unreadableKey) ?? []
            return
        }
        for item in Self.legacy where cache[item.to] == nil {
            guard backend.accounts(service: item.service).contains(item.account) else { continue }
            if let value = backend.read(service: item.service, account: item.account), !value.isEmpty {
                if backend.write(value, service: Self.service, account: item.to) { cache[item.to] = value }
            } else {
                unreadableLegacy.append("\(item.service)/\(item.account)")
            }
        }
        // One attempt only, then old items are never touched again. Anything the app could not read
        // without a dialog is listed for scripts/migrate-legacy-keychain.sh (no prompt either).
        defaults.set(unreadableLegacy, forKey: Self.unreadableKey)
        defaults.set(true, forKey: Self.migratedFlag)
    }

    public func get(_ account: String) -> String? {
        load()
        lock.lock(); defer { lock.unlock() }
        return cache[account]
    }

    public func has(_ account: String) -> Bool { get(account) != nil }

    @discardableResult
    /// Clears a legacy entry from the unreadable list once a script has imported it.
    public func resolveLegacy(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        unreadableLegacy.removeAll { $0 == name }
        defaults.set(unreadableLegacy, forKey: Self.unreadableKey)
    }

    public func set(_ value: String, for account: String) -> Bool {
        load()
        lock.lock(); defer { lock.unlock() }
        guard backend.write(value, service: Self.service, account: account) else { return false }
        cache[account] = value
        return true
    }

    /// Success means the backend confirmed deletion or the item was already absent.
    /// Keep cached state on failure so callers cannot falsely report a removed secret.
    @discardableResult
    public func remove(_ account: String) -> Bool {
        load()
        lock.lock(); defer { lock.unlock() }
        guard backend.delete(service: Self.service, account: account) else { return false }
        cache[account] = nil
        return true
    }
}

/// An in-memory Keychain for tests and snapshots. `locked` items cannot be read or removed.
public final class MemoryKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var items: [String: String] = [:]
    public var locked: Set<String> = []
    public private(set) var reads = 0
    public init(_ items: [String: String] = [:]) { self.items = items }
    static func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }

    public func accounts(service: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return items.keys.filter { $0.hasPrefix(service + "|") }.map { String($0.dropFirst(service.count + 1)) }
    }
    public func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        let key = Self.key(service, account)
        return locked.contains(key) ? nil : items[key]
    }
    public func write(_ value: String, service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[Self.key(service, account)] = value
        return true
    }
    @discardableResult
    public func delete(service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = Self.key(service, account)
        guard !locked.contains(key) else { return false }
        items[key] = nil
        return true
    }
}
