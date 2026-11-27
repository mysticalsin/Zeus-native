import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Face vault store")
struct FaceVaultStoreTests {
    /// A store in a fresh temp folder with an in-memory Keychain. Never touches the real Keychain or Zeus's folder.
    struct Fixture {
        let directory: URL
        let backend: MemoryKeychain
        let keychain: KeychainStore
        let store: FaceVaultStore

        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("face-vault-\(UUID().uuidString)", isDirectory: true)
            backend = MemoryKeychain()
            keychain = KeychainStore(backend: backend, defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.facevault.tests.\(UUID().uuidString)")!)
            store = FaceVaultStore(directory: directory, keychain: keychain)
        }

        var keyItem: String? { backend.items["\(KeychainStore.service)|\(FaceVaultStore.keyAccount)"] }
        var fileExists: Bool { FileManager.default.fileExists(atPath: store.url.path) }
        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    static func record(_ id: String, enabled: Bool = true) -> FaceRecord {
        FaceRecord(id: id, name: "Face \(id)", isEnabled: enabled, revision: 2,
                   samples: [[0.5, -0.25, 0.125, 0.3], [0.4, -0.35, 0.225, 0.2]], threshold: 0.3)
    }

    @Test func aNewStoreIsEmptyAndTouchesNothing() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .empty)
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
    }

    @Test func savedFacesComeBackAndTheFileIsPrivate() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        let faces = [Self.record("1"), Self.record("2", enabled: false)]
        #expect(fixture.store.save(faces, presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .faces(faces))
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.store.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        // The key is 32 bytes in the Keychain and never in the file.
        let key = try #require(fixture.keyItem.flatMap { FaceVault.key(fromBase64: $0) })
        let bytes = try Data(contentsOf: fixture.store.url)
        #expect(bytes.range(of: key) == nil)
        #expect(bytes.range(of: Data("samples".utf8)) == nil)
        // A second save keeps the same key.
        let before = fixture.keyItem
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.keyItem == before)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .faces([Self.record("1")]))
    }

    @Test func anUnreadableVaultIsNeverOverwritten() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        let original = try Data(contentsOf: fixture.store.url)

        // A damaged file: load says unreadable, save refuses and leaves the bytes and the key as they were.
        var damaged = original
        damaged[damaged.count / 2] ^= 0xFF
        try damaged.write(to: fixture.store.url)
        let keyBefore = fixture.keyItem
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .unreadable)
        #expect(fixture.store.save([Self.record("9")], presence: .synthetic(.save, userPresent: true)) == .refusedUnreadable)
        #expect(fixture.store.save([], presence: .synthetic(.save, userPresent: true)) == .refusedUnreadable)
        #expect(try Data(contentsOf: fixture.store.url) == damaged)
        #expect(fixture.keyItem == keyBefore)
    }

    @Test func aMissingKeyWithAFileIsUnreadableNotEmpty() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        let original = try Data(contentsOf: fixture.store.url)
        // The Keychain item is gone (a new Mac, a reset keychain): the file is not an empty vault.
        _ = fixture.keychain.remove(FaceVaultStore.keyAccount)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .unreadable)
        #expect(fixture.store.save([Self.record("2")], presence: .synthetic(.save, userPresent: true)) == .refusedUnreadable)
        #expect(try Data(contentsOf: fixture.store.url) == original)
        // And no new key was invented for the refused save.
        #expect(fixture.keyItem == nil)
    }

    @Test func aKeyThatIsNotThirtyTwoBytesIsUnreadable() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.keychain.set("short", for: FaceVaultStore.keyAccount))
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .unreadable)
    }

    @Test func deletingTheLastFaceRemovesFileAndKey() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1"), Self.record("2")], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.store.save([Self.record("2")], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.fileExists)
        #expect(fixture.keyItem != nil)
        #expect(fixture.store.save([], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .empty)
        // Saving again after that starts with a new key.
        #expect(fixture.store.save([Self.record("3")], presence: .synthetic(.save, userPresent: true)) == .saved)
        #expect(fixture.keyItem != nil)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .faces([Self.record("3")]))
    }

    @Test func aKeychainThatRefusesTheKeyWritesNoFile() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        // A store whose Keychain cannot save the new key must not leave a file nobody can open.
        let refusing = FaceVaultStore(directory: fixture.directory, keychain: KeychainStore(backend: RefusingKeychain(),
            defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.facevault.tests.\(UUID().uuidString)")!))
        #expect(refusing.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .failed)
        #expect(!FileManager.default.fileExists(atPath: refusing.url.path))
    }

    @Test func eraseRemovesAnUnreadableVaultOnlyWhenAsked() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        try Data("garbage".utf8).write(to: fixture.store.url)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .unreadable)
        #expect(fixture.store.erase())
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .empty)
        #expect(fixture.store.save([Self.record("2")], presence: .synthetic(.save, userPresent: true)) == .saved)
    }

    @Test func aMissingPresenceProofLeavesTheVaultClosed() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        let absent = FaceTemplateProof.synthetic(.save, userPresent: false)
        let readOnly = FaceTemplateProof.synthetic(.read, userPresent: true)
        #expect(fixture.store.save([Self.record("1")], presence: absent) == .needsPresence)
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.save([Self.record("1")], presence: readOnly) == .needsPresence)
        #expect(fixture.store.save([Self.record("1")], presence: .synthetic(.save, userPresent: true)) == .saved)
        let saved = try Data(contentsOf: fixture.store.url)
        let key = fixture.keyItem
        #expect(fixture.store.load(presence: .synthetic(.save, userPresent: true)) == .needsPresence)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: false)) == .needsPresence)
        #expect(try Data(contentsOf: fixture.store.url) == saved)
        #expect(fixture.keyItem == key)
        #expect(fixture.store.load(presence: .synthetic(.read, userPresent: true)) == .faces([Self.record("1")]))
    }
}

private final class RefusingKeychain: KeychainBackend, @unchecked Sendable {
    func accounts(service: String) -> [String] { [] }
    func read(service: String, account: String) -> String? { nil }
    func write(_ value: String, service: String, account: String) -> Bool { false }
    func delete(service: String, account: String) -> Bool { true }
}
