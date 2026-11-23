import Foundation
import Testing
import ZeusCore
@testable import Zeus

@Suite("Face vault store")
struct FaceVaultStoreTests {
    /// A store in a fresh temp folder with an in-memory keychain. Never touches the real keychain or Zeus's folder.
    struct Fixture {
        let directory: URL
        let backend: MemoryKeychain
        let keychain: KeychainStore
        let templates: MemoryFaceTemplateKeychain
        let store: FaceVaultStore

        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("face-vault-\(UUID().uuidString)", isDirectory: true)
            backend = MemoryKeychain()
            keychain = KeychainStore(backend: backend, defaults: UserDefaults(suiteName: NSTemporaryDirectory() + "zeus.facevault.tests.\(UUID().uuidString)")!)
            templates = MemoryFaceTemplateKeychain()
            store = FaceVaultStore(directory: directory, keychain: keychain, templates: templates)
        }

        var keyItem: String? { backend.items["\(KeychainStore.service)|\(FaceVaultStore.keyAccount)"] }
        var template: FaceTemplateRecord? { templates.item(account: FaceVaultStore.templateAccount) }
        var fileExists: Bool { FileManager.default.fileExists(atPath: store.url.path) }
        var metaExists: Bool { FileManager.default.fileExists(atPath: store.metaURL.path) }
        func cleanUp() { try? FileManager.default.removeItem(at: directory) }

        func plantOld(_ faces: [FaceRecord], keyText: String? = nil) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let key = FaceVault.makeKey()
            let sealed = try FaceVault.seal(FaceVaultContents(faces: faces), key: key)
            try sealed.write(to: store.url)
            #expect(keychain.set(keyText ?? key.base64EncodedString(), for: FaceVaultStore.keyAccount))
        }
    }

    static func record(_ id: String, enabled: Bool = true) -> FaceRecord {
        FaceRecord(id: id, name: "Face \(id)", isEnabled: enabled, revision: 2,
                   samples: [[0.5, -0.25, 0.125, 0.3], [0.4, -0.35, 0.225, 0.2]], threshold: 0.3)
    }

    @Test func aNewStoreIsEmptyAndTouchesNothing() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.load() == .empty)
        #expect(!fixture.fileExists)
        #expect(!fixture.metaExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.template == nil)
    }

    @Test func savedFacesComeBackAndTheTemplateIsProtected() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        let faces = [Self.record("1"), Self.record("2", enabled: false)]
        #expect(fixture.store.save(faces) == .saved)
        #expect(fixture.store.load() == .faces(faces.map { $0.withoutSamples() }))
        var read: [FaceRecord] = []
        #expect(fixture.store.withTemplates { read = $0 } == .success(()))
        #expect(read == faces)
        #expect(fixture.template?.protection == .biometryCurrentSetOrDevicePasscode)
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.store.metaURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let meta = try Data(contentsOf: fixture.store.metaURL)
        #expect(meta.range(of: Data("0.5".utf8)) == nil)
        #expect(meta.range(of: Data("-0.25".utf8)) == nil)
        #expect(fixture.store.save([Self.record("1")]) == .saved)
        #expect(fixture.store.load() == .faces([Self.record("1").withoutSamples()]))
    }

    @Test func anUnreadableVaultIsNeverOverwritten() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let damaged = Data("not a vault".utf8)
        try damaged.write(to: fixture.store.url)
        #expect(fixture.store.load() == .unreadable)
        #expect(fixture.store.save([Self.record("9")]) == .refusedUnreadable)
        #expect(fixture.store.save([]) == .refusedUnreadable)
        #expect(try Data(contentsOf: fixture.store.url) == damaged)
        #expect(fixture.template == nil)
    }

    @Test func aMissingKeyWithAFileIsUnreadableNotEmpty() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        try fixture.plantOld([Self.record("1")])
        let original = try Data(contentsOf: fixture.store.url)
        _ = fixture.keychain.remove(FaceVaultStore.keyAccount)
        #expect(fixture.store.load() == .unreadable)
        #expect(fixture.store.save([Self.record("2")]) == .refusedUnreadable)
        #expect(try Data(contentsOf: fixture.store.url) == original)
        #expect(fixture.template == nil)
        #expect(fixture.keyItem == nil)
    }

    @Test func aKeyThatIsNotThirtyTwoBytesIsUnreadable() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        try fixture.plantOld([Self.record("1")], keyText: "short")
        #expect(fixture.store.load() == .unreadable)
        #expect(fixture.template == nil)
    }

    @Test func deletingTheLastFaceRemovesFileAndKey() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        #expect(fixture.store.save([Self.record("1"), Self.record("2")]) == .saved)
        #expect(fixture.store.save([Self.record("2")]) == .saved)
        #expect(fixture.metaExists)
        #expect(fixture.template != nil)
        #expect(fixture.store.save([]) == .saved)
        #expect(!fixture.fileExists)
        #expect(!fixture.metaExists)
        #expect(fixture.template == nil)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.load() == .empty)
        #expect(fixture.store.save([Self.record("3")]) == .saved)
        #expect(fixture.store.load() == .faces([Self.record("3").withoutSamples()]))
    }

    @Test func aKeychainThatRefusesTheKeyWritesNoFile() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        fixture.templates.failWrites = .unavailable
        #expect(fixture.store.save([Self.record("1")]) == .failed)
        #expect(!fixture.fileExists)
        #expect(!fixture.metaExists)
        #expect(fixture.template == nil)
    }

    @Test func aCancelledSaveStoresNothing() {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        fixture.templates.failWrites = .cancelled
        #expect(fixture.store.save([Self.record("1")]) == .failed)
        #expect(fixture.template == nil)
        #expect(fixture.store.load() == .empty)
    }

    @Test func eraseRemovesAnUnreadableVaultOnlyWhenAsked() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: fixture.store.url)
        #expect(fixture.store.load() == .unreadable)
        #expect(fixture.store.erase())
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.store.load() == .empty)
        #expect(fixture.store.save([Self.record("2")]) == .saved)
    }

    @Test func anOldVaultMovesIntoTheProtectedItemOnlyAfterTheCopyMatches() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        let face = Self.record("1")
        try fixture.plantOld([face])
        #expect(fixture.fileExists)
        #expect(fixture.store.load() == .faces([face.withoutSamples()]))
        #expect(!fixture.fileExists)
        #expect(fixture.keyItem == nil)
        #expect(fixture.template?.protection == FaceVaultStore.protection)
        var read: [FaceRecord] = []
        #expect(fixture.store.withTemplates { read = $0 } == .success(()))
        #expect(read == [face])
    }

    @Test func aCancelledMigrationKeepsTheOldCopy() throws {
        let fixture = Fixture(); defer { fixture.cleanUp() }
        try fixture.plantOld([Self.record("1")])
        let original = try Data(contentsOf: fixture.store.url)
        let key = fixture.keyItem
        fixture.templates.failWrites = .cancelled
        #expect(fixture.store.load() == .unreadable)
        #expect(try Data(contentsOf: fixture.store.url) == original)
        #expect(fixture.keyItem == key)
        #expect(fixture.template == nil)
        #expect(!fixture.metaExists)
    }
}
