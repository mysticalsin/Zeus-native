import Foundation

/// A Keychain operation failed for a reason other than a missing item.
public enum KeychainBackendError: Error, Equatable, Sendable {
    /// The account list could not be read. An empty list means there are no items, not that the read failed.
    case listingFailed
}

/// Where secrets physically live. The real one is the macOS Keychain; tests use memory.
public protocol KeychainBackend: Sendable {
    /// Every account under `service` (attributes only, no secrets).
    /// Throws when the list cannot be read. A missing item is an empty list, not an error.
    func accounts(service: String) throws -> [String]
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
    /// Alias value removed while loading. A failed OpenAI `remove` writes it back.
    private var aliasRemovedAtLoad: String?
    /// Set for the load that `remove` itself triggers, so that load keeps the alias value.
    private var keepAliasSnapshot = false
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
        defer { if !keepAliasSnapshot { aliasRemovedAtLoad = nil } }
        guard !loaded else { return }
        let names: [String]
        do { names = try backend.accounts(service: Self.service) }
        catch { return }
        loaded = true
        for account in names {
            if let value = backend.read(service: Self.service, account: account) { cache[account] = value }
        }
        // Read the legacy spelling from the cache just filled, write the canonical account, read that
        // account back, then delete the legacy spelling. A launch with no legacy spelling does not
        // read the backend again. Leaving assistant.key.openai in place makes the next load copy it back.
        let migrated = AssistantKeyAccount.migrateOpenAI(
            get: { cache[$0] },
            writeCanonical: { value in
                guard backend.write(value, service: Self.service, account: AssistantKeyAccount.canonicalOpenAI) else { return false }
                guard let stored = backend.read(service: Self.service, account: AssistantKeyAccount.canonicalOpenAI),
                      stored == value else { return false }
                cache[AssistantKeyAccount.canonicalOpenAI] = stored
                return true
            },
            deleteAlias: {
                // Not-found is success. A real refusal leaves the alias cached for the next launch.
                let saved = cache[AssistantKeyAccount.aliasOpenAI]
                switch Self.deleteOutcome(AssistantKeyAccount.aliasOpenAI, backend: backend) {
                case .removed:
                    cache[AssistantKeyAccount.aliasOpenAI] = nil
                    if let saved { aliasRemovedAtLoad = saved }
                    return true
                case .absent:
                    cache[AssistantKeyAccount.aliasOpenAI] = nil
                    return true
                case .failed:
                    return false
                }
            }
        )
        if let migrated { cache[AssistantKeyAccount.canonicalOpenAI] = migrated }
        guard !defaults.bool(forKey: Self.migratedFlag) else {
            unreadableLegacy = defaults.stringArray(forKey: Self.unreadableKey) ?? []
            return
        }
        for item in Self.legacy where cache[item.to] == nil {
            let listed: [String]
            do { listed = try backend.accounts(service: item.service) }
            catch {
                unreadableLegacy.append("\(item.service)/\(item.account)")
                continue
            }
            guard listed.contains(item.account) else { continue }
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
        } else if let listed = try? backend.accounts(service: Self.service), !listed.contains(account) {
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

    /// Success means every targeted account was deleted or already absent.
    /// The legacy OpenAI spelling is removed before the canonical account. A refusal restores any
    /// spelling already removed in this call, so a partial delete cannot drop the canonical secret
    /// or leave `assistant.key.openai` behind to be copied back.
    @discardableResult
    public func remove(_ account: String) -> Bool {
        let openAI = account == AssistantKeyAccount.canonicalOpenAI || account == AssistantKeyAccount.aliasOpenAI
        if openAI {
            lock.lock()
            keepAliasSnapshot = true
            aliasRemovedAtLoad = nil
            lock.unlock()
        }
        load()
        lock.lock(); defer { lock.unlock() }
        if openAI { keepAliasSnapshot = false }
        let removed = deleteAccounts(Self.removalAccounts(for: account))
        if openAI, !removed {
            _ = restoreAliasRemovedAtLoad()
            return false
        }
        aliasRemovedAtLoad = nil
        return removed
    }

    /// Deletes one account. Not-found is success. Unlike `remove`, this does not delete the other
    /// OpenAI spelling. Migration uses it so a cleanup of `assistant.key.openai` cannot erase the
    /// canonical secret that was just verified.
    @discardableResult
    public func deleteAccount(_ account: String) -> Bool {
        load()
        lock.lock(); defer { lock.unlock() }
        return deleteAccounts([account])
    }

    /// Legacy spelling first, canonical account last. A refused legacy delete never reaches the canonical item.
    static func removalAccounts(for account: String) -> [String] {
        guard account == AssistantKeyAccount.canonicalOpenAI || account == AssistantKeyAccount.aliasOpenAI else {
            return [account]
        }
        return [AssistantKeyAccount.aliasOpenAI, AssistantKeyAccount.canonicalOpenAI]
    }

    /// Writes `value` and reads it back. A write that does not return the same bytes is not stored.
    private func verifiedWrite(_ value: String, account: String) -> Bool {
        guard backend.write(value, service: Self.service, account: account) else { return false }
        return backend.read(service: Self.service, account: account) == value
    }

    private func restoreRemoved(_ removed: [(account: String, value: String)]) {
        for prior in removed.reversed() {
            if verifiedWrite(prior.value, account: prior.account) || verifiedWrite(prior.value, account: prior.account) {
                cache[prior.account] = prior.value
            } else {
                cache[prior.account] = prior.value
            }
        }
    }

    private func deleteAccounts(_ targets: [String]) -> Bool {
        var removed: [(account: String, value: String)] = []
        for item in targets {
            let saved = cache[item] ?? backend.read(service: Self.service, account: item)
            // Do not delete a secret until a write of that same value has been read back.
            if let saved, !verifiedWrite(saved, account: item) {
                restoreRemoved(removed)
                return false
            }
            switch Self.deleteOutcome(item, backend: backend) {
            case .removed:
                cache[item] = nil
                if let saved { removed.append((item, saved)) }
            case .absent:
                cache[item] = nil
            case .failed:
                restoreRemoved(removed)
                return false
            }
        }
        return true
    }

    /// `remove` of an OpenAI spelling that fails puts back an alias this load already deleted.
    /// A failed write leaves the snapshot in place and does not claim the alias was restored.
    @discardableResult
    private func restoreAliasRemovedAtLoad() -> Bool {
        guard let value = aliasRemovedAtLoad else { return true }
        guard let listed = try? backend.accounts(service: Self.service) else { return false }
        guard listed.contains(AssistantKeyAccount.canonicalOpenAI) else { return false }
        let account = AssistantKeyAccount.aliasOpenAI
        guard !listed.contains(account) else {
            aliasRemovedAtLoad = nil
            return true
        }
        guard verifiedWrite(value, account: account) || verifiedWrite(value, account: account) else { return false }
        aliasRemovedAtLoad = nil
        cache[account] = value
        return true
    }

    /// `errSecSuccess` and `errSecItemNotFound` are the only successful delete results.
    /// Any other status is failure. A list that throws is failure too: a locked keychain must not
    /// look like an empty one, or `remove` would report success while the item stays.
    /// A false delete of an item that can still be read is failure. A false delete of an item that
    /// a successful list and read both show is gone is not-found, which is success.
    private static func deleteOutcome(_ account: String, backend: KeychainBackend) -> AccountDelete {
        let present: Bool
        do { present = try backend.accounts(service: service).contains(account) }
        catch { return .failed }
        let deleted = backend.delete(service: service, account: account)
        if !deleted {
            if backend.read(service: service, account: account) != nil { return .failed }
            do {
                if try backend.accounts(service: service).contains(account) { return .failed }
            } catch { return .failed }
            return .absent
        }
        do {
            if try backend.accounts(service: service).contains(account) { return .failed }
        } catch { return .failed }
        if backend.read(service: service, account: account) != nil { return .failed }
        return present ? .removed : .absent
    }

    private enum AccountDelete { case removed, absent, failed }
}

/// An in-memory Keychain for tests and snapshots. `locked` items cannot be read or removed.
public final class MemoryKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var items: [String: String] = [:]
    public var locked: Set<String> = []
    public private(set) var reads = 0
    public init(_ items: [String: String] = [:]) { self.items = items }
    static func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }

    public func accounts(service: String) throws -> [String] {
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
    /// Reads the legacy value, writes the canonical account, reads that account back, and only then
    /// deletes `assistant.key.openai`. When the canonical value is already present, that value stays
    /// and a stale alias is deleted. A failed delete is tried once more. Nil means the migration is
    /// not done: the canonical write failed, the stored bytes did not match, or the alias is still
    /// present. A non-nil result is the canonical value, and only after the alias is gone.
    public static func migrateOpenAI(
        get: (String) -> String?,
        writeCanonical: (String) -> Bool,
        deleteAlias: () -> Bool
    ) -> String? {
        if let canonical = nonempty(get(canonicalOpenAI)) {
            guard nonempty(get(aliasOpenAI)) != nil else { return canonical }
            guard deleteAliasConfirmed(deleteAlias) else { return nil }
            return canonical
        }
        guard let alias = nonempty(get(aliasOpenAI)) else { return nil }
        guard writeCanonical(alias),
              let stored = nonempty(get(canonicalOpenAI)),
              stored == alias else { return nil }
        guard deleteAliasConfirmed(deleteAlias) else { return nil }
        return stored
    }

    private static func deleteAliasConfirmed(_ deleteAlias: () -> Bool) -> Bool {
        if deleteAlias() { return true }
        return deleteAlias()
    }
}
