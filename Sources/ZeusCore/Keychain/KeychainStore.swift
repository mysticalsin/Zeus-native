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
    private let now: @Sendable () -> Date
    private var lastRefresh: [String: Date] = [:]
    /// Least time between two backend re-reads of the same account.
    public static let refreshInterval: TimeInterval = 5
    /// Legacy items that exist but could not be read without a dialog.
    public private(set) var unreadableLegacy: [String] = []

    public init(backend: KeychainBackend, defaults: UserDefaults = .standard,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.defaults = defaults
        self.now = now
    }

    /// Reads everything once (and migrates once). Safe to call again; later calls do nothing.
    public func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        for account in backend.accounts(service: Self.service) {
            if let value = backend.read(service: Self.service, account: account) { cache[account] = value }
        }
        if AssistantKeyAccount.nonempty(cache[AssistantKeyAccount.canonicalOpenAI]) == nil,
           let alias = AssistantKeyAccount.nonempty(cache[AssistantKeyAccount.aliasOpenAI]),
           backend.write(alias, service: Self.service, account: AssistantKeyAccount.canonicalOpenAI) {
            cache[AssistantKeyAccount.canonicalOpenAI] = alias
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

    /// Re-reads one account from the backend so a value saved outside this process (a script, another
    /// ZEUS) shows up without a restart. The backend is asked at most once per `refreshInterval` per
    /// account; inside that window the cached value is returned. An account that no longer exists is
    /// cleared; one that exists but cannot be read without a dialog keeps its cached value.
    @discardableResult
    public func refresh(_ account: String) -> String? {
        load()
        lock.lock(); defer { lock.unlock() }
        let stamp = now()
        if let last = lastRefresh[account], stamp.timeIntervalSince(last) < Self.refreshInterval {
            return cache[account]
        }
        lastRefresh[account] = stamp
        if let value = backend.read(service: Self.service, account: account) {
            cache[account] = value
        } else if !backend.accounts(service: Self.service).contains(account) {
            cache[account] = nil
        }
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

/// The speech card stores the direct key at `assistant.key.openAI`. An older brain path read
/// `assistant.key.openai`. Readers check both. Writers and the one-time copy use the canonical account.
public enum AssistantKeyAccount {
    public static let canonicalOpenAI = "assistant.key.openAI"
    public static let aliasOpenAI = "assistant.key.openai"

    public static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Canonical account first, then the lowercase alias.
    public static func readOpenAI(_ get: (String) -> String?) -> String? {
        if let value = nonempty(get(canonicalOpenAI)) { return value }
        return nonempty(get(aliasOpenAI))
    }

    /// Writes the trimmed value through the caller, which must target `canonicalOpenAI`.
    @discardableResult
    public static func writeOpenAI(_ value: String, write: (String) -> Bool) -> Bool {
        guard let trimmed = nonempty(value) else { return false }
        return write(trimmed)
    }

    /// Copies the alias into the canonical account when the canonical account is empty.
    /// A canonical value is left in place. Returns the canonical value after the attempt.
    public static func migrateOpenAI(get: (String) -> String?, writeCanonical: (String) -> Bool) -> String? {
        if let canonical = nonempty(get(canonicalOpenAI)) { return canonical }
        guard let alias = nonempty(get(aliasOpenAI)) else { return nil }
        if writeCanonical(alias), let stored = nonempty(get(canonicalOpenAI)) { return stored }
        return alias
    }
}
