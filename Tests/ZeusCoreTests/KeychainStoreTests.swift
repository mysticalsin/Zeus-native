import Foundation
import Testing
@testable import ZeusCore

@Suite struct KeychainStoreTests {
    func defaults() -> UserDefaults {
        let name = "zeus.keychain.tests.\(UUID().uuidString)"
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
        store.remove("assistant.key.openAI")
        #expect(!store.has("assistant.key.openAI"))
        #expect(backend.items.isEmpty)
    }
}
