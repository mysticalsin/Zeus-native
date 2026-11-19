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
}
