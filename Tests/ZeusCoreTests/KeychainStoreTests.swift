import Foundation
import Testing
@testable import ZeusCore

@Suite struct KeychainStoreTests {
    func defaults() -> UserDefaults {
        let name = NSTemporaryDirectory() + "zeus.keychain.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func readsOnceThenServesFromMemory() {
        let backend = MemoryKeychain(["com.zeus.app|license.key": "abc"])
        let store = KeychainStore(backend: backend, defaults: defaults())
        _ = store.get("license.key")
        let afterFirst = backend.reads
        for _ in 0..<20 { _ = store.get("license.key") }
        #expect(store.get("license.key") == "abc")
        #expect(backend.reads == afterFirst)
    }

    @Test func migratesElevenLabsOnceAndStopsTouchingOldItems() {
        let backend = MemoryKeychain(["com.zeus.elevenlabs|api-key": "sk-test", "com.zeus.worker|url": "https://w"])
        let flags = defaults()
        let store = KeychainStore(backend: backend, defaults: flags)
        #expect(store.get("elevenlabs.api-key") == "sk-test")
        #expect(store.get("worker.url") == "https://w")
        #expect(backend.items["com.zeus.app|elevenlabs.api-key"] == "sk-test")
        #expect(flags.bool(forKey: "keychain.migrated.v1"))
        // A fresh launch reads only com.zeus.app.
        let relaunch = MemoryKeychain(backend.items)
        let again = KeychainStore(backend: relaunch, defaults: flags)
        again.load()
        let appItems = relaunch.accounts(service: "com.zeus.app").count
        #expect(relaunch.reads == appItems)
        #expect(again.get("elevenlabs.api-key") == "sk-test")
    }

    @Test func unreadableLegacyItemIsSkippedNotPrompted() {
        let backend = MemoryKeychain(["com.zeus.worker|token": "t"])
        backend.locked = ["com.zeus.worker|token"]
        let flags = defaults()
        let store = KeychainStore(backend: backend, defaults: flags)
        #expect(store.get("worker.token") == nil)
        #expect(store.unreadableLegacy == ["com.zeus.worker/token"])
        #expect(flags.bool(forKey: "keychain.migrated.v1"))
        #expect(flags.stringArray(forKey: "keychain.legacy.unreadable") == ["com.zeus.worker/token"])
    }

    @Test func setAndRemoveKeepCacheInStep() {
        let backend = MemoryKeychain()
        let store = KeychainStore(backend: backend, defaults: defaults())
        store.set("k", for: "assistant.key.openAI")
        #expect(store.has("assistant.key.openAI"))
        #expect(store.remove("assistant.key.openAI"))
        #expect(!store.has("assistant.key.openAI"))
        #expect(backend.items.isEmpty)
    }

    @Test func deniedRemovalRetainsSavedStateAndSurvivesRelaunchUntilConfirmedRetry() {
        let account = "assistant.key.openAI"
        let backend = MemoryKeychain(["com.zeus.app|\(account)": "synthetic-value"])
        let flags = defaults()
        let store = KeychainStore(backend: backend, defaults: flags)
        #expect(store.has(account))
        backend.locked = ["com.zeus.app|\(account)"]
        #expect(!store.remove(account))
        #expect(store.has(account))
        #expect(backend.items["com.zeus.app|\(account)"] == "synthetic-value")

        backend.locked = []
        let relaunched = KeychainStore(backend: backend, defaults: flags)
        #expect(relaunched.has(account))
        #expect(relaunched.remove(account))
        #expect(!relaunched.has(account))
        let nextLaunch = KeychainStore(backend: backend, defaults: flags)
        #expect(!nextLaunch.has(account))
    }

    @Test func removalOfAbsentSecretIsIdempotentAndDoesNotTouchOtherAccounts() {
        let backend = MemoryKeychain(["com.zeus.app|unrelated": "retained"])
        let flags = defaults()
        let store = KeychainStore(backend: backend, defaults: flags)
        #expect(store.remove("absent"))
        #expect(store.remove("absent"))
        #expect(store.get("unrelated") == "retained")
        #expect(backend.items == ["com.zeus.app|unrelated": "retained"])
    }

    /// A clock the test moves by hand.
    final class TestClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    @Test func refreshPicksUpAValueSavedOutsideTheStore() {
        let backend = MemoryKeychain(["com.zeus.app|elevenlabs.voice-id": "STOCK"])
        let clock = TestClock()
        let store = KeychainStore(backend: backend, defaults: defaults(), now: { clock.now })
        #expect(store.get("elevenlabs.voice-id") == "STOCK")
        _ = backend.write("TONY", service: "com.zeus.app", account: "elevenlabs.voice-id")
        #expect(store.get("elevenlabs.voice-id") == "STOCK")
        clock.advance(6)
        #expect(store.refresh("elevenlabs.voice-id") == "TONY")
        #expect(store.get("elevenlabs.voice-id") == "TONY")
    }

    @Test func refreshClearsAnAccountDeletedOutsideTheStoreButKeepsAnUnreadableOne() {
        let backend = MemoryKeychain(["com.zeus.app|a": "1", "com.zeus.app|b": "2"])
        let clock = TestClock()
        let store = KeychainStore(backend: backend, defaults: defaults(), now: { clock.now })
        #expect(store.get("a") == "1" && store.get("b") == "2")
        backend.delete(service: "com.zeus.app", account: "a")
        backend.locked = ["com.zeus.app|b"]
        clock.advance(6)
        #expect(store.refresh("a") == nil)
        #expect(store.get("a") == nil)
        #expect(store.refresh("b") == "2")
    }

    @Test func refreshReadsTheBackendAtMostOncePerFiveSecondsPerAccount() {
        let backend = MemoryKeychain(["com.zeus.app|v": "1", "com.zeus.app|w": "9"])
        let clock = TestClock()
        let store = KeychainStore(backend: backend, defaults: defaults(), now: { clock.now })
        store.load()
        clock.advance(6)
        let before = backend.reads
        _ = store.refresh("v")
        for _ in 0..<50 { _ = store.refresh("v") }
        #expect(backend.reads == before + 1)
        _ = store.refresh("w")
        #expect(backend.reads == before + 2)
        clock.advance(5)
        _ = backend.write("2", service: "com.zeus.app", account: "v")
        #expect(store.refresh("v") == "2")
        #expect(backend.reads == before + 3)
    }

    /// S04-01. The speech card writes `assistant.key.openAI`. An older reader used `assistant.key.openai`.
    @Test func openAIKeyReadsBothSpellingsWritesCanonicalAndMigrates() {
        let aliasBackend = MemoryKeychain(["com.zeus.app|assistant.key.openai": "sk-alias"])
        let aliasOnly = KeychainStore(backend: aliasBackend, defaults: defaults())
        #expect(AssistantKeyAccount.readOpenAI(aliasOnly.get) == "sk-alias")
        #expect(AssistantKeyAccount.migrateOpenAI(
            get: aliasOnly.get,
            writeCanonical: { aliasOnly.set($0, for: AssistantKeyAccount.canonicalOpenAI) },
            deleteAlias: { aliasBackend.delete(service: KeychainStore.service, account: AssistantKeyAccount.aliasOpenAI) }
        ) == "sk-alias")
        #expect(aliasOnly.get(AssistantKeyAccount.canonicalOpenAI) == "sk-alias")
        #expect(aliasOnly.get(AssistantKeyAccount.aliasOpenAI) == nil)

        let canonical = KeychainStore(backend: MemoryKeychain(), defaults: defaults())
        #expect(AssistantKeyAccount.writeOpenAI("sk-new", write: { canonical.set($0, for: AssistantKeyAccount.canonicalOpenAI) }))
        #expect(canonical.get(AssistantKeyAccount.canonicalOpenAI) == "sk-new")
        #expect(canonical.get(AssistantKeyAccount.aliasOpenAI) == nil)
        #expect(AssistantKeyAccount.readOpenAI(canonical.get) == "sk-new")

        let bothBackend = MemoryKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-alias",
        ])
        let both = KeychainStore(backend: bothBackend, defaults: defaults())
        #expect(AssistantKeyAccount.readOpenAI(both.get) == "sk-canonical")
        #expect(AssistantKeyAccount.migrateOpenAI(
            get: both.get,
            writeCanonical: { both.set($0, for: AssistantKeyAccount.canonicalOpenAI) },
            deleteAlias: { bothBackend.delete(service: KeychainStore.service, account: AssistantKeyAccount.aliasOpenAI) }
        ) == "sk-canonical")
        #expect(both.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
    }

    /// Z103-1. `remove()` deletes only `assistant.key.openAI`, and migration leaves `assistant.key.openai`.
    /// The next load then copies the legacy spelling back into the canonical account.
    @Test func removingTheOpenAIKeyDeletesBothSpellingsAndMigrationDropsTheLegacyAccount() {
        let aliasBackend = MemoryKeychain(["com.zeus.app|assistant.key.openai": "sk-legacy"])
        let aliasStore = KeychainStore(backend: aliasBackend, defaults: defaults())
        #expect(aliasStore.get(AssistantKeyAccount.canonicalOpenAI) == "sk-legacy")
        #expect(aliasBackend.items["com.zeus.app|assistant.key.openai"] == nil)
        #expect(aliasStore.get(AssistantKeyAccount.aliasOpenAI) == nil)

        let both = MemoryKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        let store = KeychainStore(backend: both, defaults: defaults())
        #expect(store.remove(AssistantKeyAccount.canonicalOpenAI))
        #expect(both.items["com.zeus.app|assistant.key.openAI"] == nil)
        #expect(both.items["com.zeus.app|assistant.key.openai"] == nil)
        let relaunch = KeychainStore(backend: both, defaults: defaults())
        #expect(AssistantKeyAccount.readOpenAI(relaunch.get) == nil)
    }

    /// The legacy spelling is deleted first. A refused legacy delete must leave the canonical secret.
    @Test func legacyDeleteFailureKeepsTheCanonicalSecret() {
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        backend.failDelete = [AssistantKeyAccount.aliasOpenAI]
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(!store.remove(AssistantKeyAccount.canonicalOpenAI))
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
        #expect(store.get(AssistantKeyAccount.aliasOpenAI) == "sk-legacy")
    }

    /// Removal order is legacy, then canonical, for either requested spelling.
    @Test func openAIRemovalDeletesTheLegacySpellingBeforeTheCanonicalAccount() {
        let legacyFirst = [AssistantKeyAccount.aliasOpenAI, AssistantKeyAccount.canonicalOpenAI]
        #expect(KeychainStore.removalAccounts(for: AssistantKeyAccount.canonicalOpenAI) == legacyFirst)
        #expect(KeychainStore.removalAccounts(for: AssistantKeyAccount.aliasOpenAI) == legacyFirst)
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.remove(AssistantKeyAccount.canonicalOpenAI))
        #expect(backend.deleteLog.first == AssistantKeyAccount.aliasOpenAI)
        #expect(backend.deleteLog.last == AssistantKeyAccount.canonicalOpenAI)
        #expect(backend.items.isEmpty)
    }

    /// `errSecItemNotFound` is success. A missing legacy item must not block, or undo, the canonical delete.
    @Test func absentLegacyDeleteIsSuccessAndTheCanonicalSecretIsRemoved() {
        let backend = DeleteInjectionKeychain(["com.zeus.app|assistant.key.openAI": "sk-canonical"])
        backend.absentDeleteReturnsFalse = true
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.remove(AssistantKeyAccount.canonicalOpenAI))
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] == nil)
        #expect(!store.has(AssistantKeyAccount.canonicalOpenAI))
    }

    /// A canonical delete that fails after the legacy item was removed is rolled back. The secret stays.
    @Test func canonicalDeleteFailureRestoresTheLegacyAccount() {
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        backend.failDelete = [AssistantKeyAccount.canonicalOpenAI]
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(!store.remove(AssistantKeyAccount.aliasOpenAI))
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
        #expect(store.get(AssistantKeyAccount.aliasOpenAI) == "sk-legacy")
    }

    /// Both spellings at launch: the alias is stale and has to go. The canonical value stays.
    @Test func loadDropsAStaleAliasWhenBothOpenAIAccountsExist() {
        let backend = MemoryKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == nil)
        #expect(store.get(AssistantKeyAccount.aliasOpenAI) == nil)
    }

    /// A refused alias delete is not "migrated". The alias is still there for the next attempt.
    @Test func failedAliasDeleteDuringLoadLeavesTheStaleAlias() {
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        backend.failDelete = [AssistantKeyAccount.aliasOpenAI]
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
        #expect(store.get(AssistantKeyAccount.aliasOpenAI) == "sk-legacy")
    }

    @Test func migrateOpenAIDoesNotReportDoneWhenAliasDeleteKeepsFailing() {
        var stored = [AssistantKeyAccount.aliasOpenAI: "sk-legacy"]
        var attempts = 0
        let result = AssistantKeyAccount.migrateOpenAI(
            get: { stored[$0] },
            writeCanonical: { value in
                stored[AssistantKeyAccount.canonicalOpenAI] = value
                return true
            },
            deleteAlias: {
                attempts += 1
                return false
            })
        #expect(result == nil)
        #expect(attempts == 2)
        #expect(stored[AssistantKeyAccount.aliasOpenAI] == "sk-legacy")
        #expect(stored[AssistantKeyAccount.canonicalOpenAI] == "sk-legacy")
    }

    @Test func migrateOpenAIRetriesAFailedAliasDeleteBeforeReportingDone() {
        var stored = [AssistantKeyAccount.aliasOpenAI: "sk-legacy"]
        var attempts = 0
        let result = AssistantKeyAccount.migrateOpenAI(
            get: { stored[$0] },
            writeCanonical: { value in
                stored[AssistantKeyAccount.canonicalOpenAI] = value
                return true
            },
            deleteAlias: {
                attempts += 1
                guard attempts > 1 else { return false }
                stored[AssistantKeyAccount.aliasOpenAI] = nil
                return true
            })
        #expect(result == "sk-legacy")
        #expect(attempts == 2)
        #expect(stored[AssistantKeyAccount.aliasOpenAI] == nil)
    }

    @Test func migrateOpenAIDoesNotReportDoneWhenAStaleAliasSurvives() {
        var stored = [
            AssistantKeyAccount.canonicalOpenAI: "sk-canonical",
            AssistantKeyAccount.aliasOpenAI: "sk-legacy",
        ]
        var attempts = 0
        let failed = AssistantKeyAccount.migrateOpenAI(
            get: { stored[$0] },
            writeCanonical: { _ in Issue.record("canonical value was already present"); return false },
            deleteAlias: {
                attempts += 1
                return false
            })
        #expect(failed == nil)
        #expect(attempts == 2)
        #expect(stored[AssistantKeyAccount.aliasOpenAI] == "sk-legacy")

        let dropped = AssistantKeyAccount.migrateOpenAI(
            get: { stored[$0] },
            writeCanonical: { _ in Issue.record("canonical value was already present"); return false },
            deleteAlias: {
                stored[AssistantKeyAccount.aliasOpenAI] = nil
                return true
            })
        #expect(dropped == "sk-canonical")
        #expect(stored[AssistantKeyAccount.aliasOpenAI] == nil)
    }

    /// A failed canonical write is not a migration. Nil is the only result that says it did not happen.
    @Test func migrateOpenAIReturnsNilWhenTheCanonicalWriteFails() {
        var stored = [AssistantKeyAccount.aliasOpenAI: "sk-legacy"]
        var deleted = false
        let result = AssistantKeyAccount.migrateOpenAI(
            get: { stored[$0] },
            writeCanonical: { _ in false },
            deleteAlias: { deleted = true; return true })
        #expect(result == nil)
        #expect(!deleted)
        #expect(stored[AssistantKeyAccount.canonicalOpenAI] == nil)
        #expect(stored[AssistantKeyAccount.aliasOpenAI] == "sk-legacy")
    }

    /// A locked keychain lists no accounts and refuses the delete. The item is still there, so removal failed.
    @Test func lockedKeychainDeleteDoesNotReportSuccessWhileTheItemStays() {
        let backend = LockedListingKeychain(["com.zeus.app|license.key": "secret"])
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.remove("license.key") == false)
        #expect(backend.items["com.zeus.app|license.key"] == "secret")
    }

    /// A canonical delete that fails must not lose the legacy secret when putting it back fails.
    @Test func failedWriteBackDoesNotDropTheDeletedSecret() {
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        backend.failDelete = [AssistantKeyAccount.canonicalOpenAI]
        backend.failWrite = [AssistantKeyAccount.aliasOpenAI]
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.remove(AssistantKeyAccount.canonicalOpenAI) == false)
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
    }

    /// The alias removed at load has to come back if a later delete fails. A failed restore write is not success.
    @Test func restoreOfTheAliasRemovedAtLoadDoesNotIgnoreAFailedWrite() {
        let backend = DeleteInjectionKeychain([
            "com.zeus.app|assistant.key.openAI": "sk-canonical",
            "com.zeus.app|assistant.key.openai": "sk-legacy",
        ])
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == nil)
        backend.failDelete = [AssistantKeyAccount.canonicalOpenAI]
        backend.failNextWrites = 1
        #expect(store.remove(AssistantKeyAccount.aliasOpenAI) == false)
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] == "sk-canonical")
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
    }

    /// The write is echoed by the other fakes, so this one stores a different value. Verify must fail.
    @Test func migrationFailsWhenTheStoredCanonicalValueDoesNotMatchTheWrite() {
        let backend = DivergentWriteKeychain(["com.zeus.app|assistant.key.openai": "sk-legacy"])
        let store = KeychainStore(backend: backend, defaults: defaults())
        #expect(store.get(AssistantKeyAccount.canonicalOpenAI) == nil)
        #expect(backend.items["com.zeus.app|assistant.key.openai"] == "sk-legacy")
        #expect(backend.items["com.zeus.app|assistant.key.openAI"] != "sk-legacy")
    }
}

/// Lists nothing and refuses deletion, the way a locked keychain reports an error as an empty list
/// while the item remains.
final class LockedListingKeychain: KeychainBackend, @unchecked Sendable {
    var items: [String: String]
    init(_ items: [String: String]) { self.items = items }
    func accounts(service: String) -> [String] { [] }
    func read(service: String, account: String) -> String? { items["\(service)|\(account)"] }
    func write(_ value: String, service: String, account: String) -> Bool { false }
    func delete(service: String, account: String) -> Bool { false }
}

/// Accepts a write and stores a different value, so a read-back does not match what was written.
final class DivergentWriteKeychain: KeychainBackend, @unchecked Sendable {
    var items: [String: String]
    init(_ items: [String: String]) { self.items = items }
    func accounts(service: String) -> [String] {
        items.keys.filter { $0.hasPrefix(service + "|") }.map { String($0.dropFirst(service.count + 1)) }
    }
    func read(service: String, account: String) -> String? { items["\(service)|\(account)"] }
    func write(_ value: String, service: String, account: String) -> Bool {
        items["\(service)|\(account)"] = value + "-other"
        return true
    }
    func delete(service: String, account: String) -> Bool {
        items["\(service)|\(account)"] = nil
        return true
    }
}

/// A keychain whose deletes can fail while the item stays, and whose missing items can report failure.
final class DeleteInjectionKeychain: KeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    var items: [String: String]
    var failDelete: Set<String> = []
    /// Writes to these accounts return false and leave the stored bytes unchanged.
    var failWrite: Set<String> = []
    /// The next N writes fail, then writes store the value. Used when a retry must be able to succeed.
    var failNextWrites = 0
    /// When set, deleting an account that is not stored returns false. That is `errSecItemNotFound` reported as failure.
    var absentDeleteReturnsFalse = false
    private(set) var deleteLog: [String] = []

    init(_ items: [String: String] = [:]) { self.items = items }

    func accounts(service: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return items.keys.filter { $0.hasPrefix(service + "|") }.map { String($0.dropFirst(service.count + 1)) }
    }

    func read(service: String, account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items["\(service)|\(account)"]
    }

    func write(_ value: String, service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failWrite.contains(account) { return false }
        if failNextWrites > 0 {
            failNextWrites -= 1
            return false
        }
        items["\(service)|\(account)"] = value
        return true
    }

    @discardableResult
    func delete(service: String, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        deleteLog.append(account)
        let key = "\(service)|\(account)"
        guard items[key] != nil else { return !absentDeleteReturnsFalse }
        if failDelete.contains(account) { return false }
        items[key] = nil
        return true
    }
}
