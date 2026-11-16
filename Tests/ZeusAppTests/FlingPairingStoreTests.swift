import Foundation
import Testing
@testable import ZeusCore
@testable import ZeusFling

@Suite("Fling pairing store")
struct FlingPairingStoreTests {
    private let psk = Data((0..<32).map { UInt8($0 &* 7 &+ 1) })
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fling-store-\(UUID().uuidString)", isDirectory: true)
    }
    private func make(_ keychain: MemoryKeychain = MemoryKeychain(), dir: URL) -> (FlingPairingStore, MemoryKeychain) {
        (FlingPairingStore(keychain: KeychainStore(backend: keychain, defaults: UserDefaults(suiteName: "zeus.fling-store.\(UUID().uuidString)")!), directory: dir), keychain)
    }

    /// REG-691: the key lives only in the Keychain; the file holds names and dates, owner-only.
    @Test func theKeyIsOnlyInTheKeychainAndTheFileIsOwnerOnly() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, keychain) = make(dir: dir)
        #expect(store.add(id: "idB", name: "Beta", model: "Mac15,3", psk: psk, now: Date(timeIntervalSince1970: 10)))
        #expect(store.psk(for: "idB") == psk)
        #expect(keychain.items.keys.contains { $0.hasSuffix("fling.peer.idB") })
        let file = dir.appendingPathComponent("peers.json")
        let text = try Data(contentsOf: file)
        #expect(!text.contains(psk))
        #expect(!String(decoding: text, as: UTF8.self).contains(psk.base64EncodedString()))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(store.peers.map(\.name) == ["Beta"])
        #expect(store.pskTable() == ["idB": psk])
    }

    @Test func pairedMacsSurviveARelaunch() {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (first, keychain) = make(dir: dir)
        _ = first.add(id: "idB", name: "Beta", model: "m", psk: psk, now: Date())
        let (second, _) = make(keychain, dir: dir)
        #expect(second.peers.map(\.id) == ["idB"] && second.psk(for: "idB") == psk)
        #expect(second.pairedNames() == ["idB": "Beta"])
    }

    /// REG-691: Remove deletes the Keychain item and the record, and a Keychain failure keeps the record.
    @Test func removeDeletesTheKeyAndAFailureKeepsTheRecord() {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, keychain) = make(dir: dir)
        _ = store.add(id: "idB", name: "Beta", model: "m", psk: psk, now: Date())
        keychain.locked = keychain.items.keys.filter { $0.hasSuffix("fling.peer.idB") }.reduce(into: Set<String>()) { $0.insert($1) }
        #expect(!store.remove(id: "idB"))
        #expect(store.peers.count == 1)
        keychain.locked = []
        #expect(store.remove(id: "idB"))
        #expect(store.peers.isEmpty && store.psk(for: "idB") == nil)
        #expect(!keychain.items.keys.contains { $0.hasSuffix("fling.peer.idB") })
    }

    @Test func aKeychainThatRefusesTheKeyStoresNoRecord() {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FlingPairingStore(keychain: KeychainStore(backend: RefusingBackend(), defaults: UserDefaults(suiteName: "zeus.fling-store.\(UUID().uuidString)")!), directory: dir)
        #expect(!store.add(id: "idB", name: "Beta", model: "m", psk: psk, now: Date()))
        #expect(store.peers.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("peers.json").path))
    }

    @Test func aRecordWithoutItsKeyIsNotPaired() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, _) = make(dir: dir)
        _ = store.add(id: "idB", name: "Beta", model: "m", psk: psk, now: Date())
        let (lonely, _) = make(MemoryKeychain(), dir: dir)
        #expect(lonely.psk(for: "idB") == nil)
        #expect(lonely.pskTable().isEmpty && lonely.pairedNames().isEmpty)
    }
}

private final class RefusingBackend: KeychainBackend, @unchecked Sendable {
    func accounts(service: String) -> [String] { [] }
    func read(service: String, account: String) -> String? { nil }
    func write(_ value: String, service: String, account: String) -> Bool { false }
    func delete(service: String, account: String) -> Bool { true }
}

private extension Data {
    func contains(_ other: Data) -> Bool { range(of: other) != nil }
}
