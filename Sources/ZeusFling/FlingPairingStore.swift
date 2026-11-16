import Foundation
import ZeusCore

public struct FlingPairedPeer: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var model: String
    public var pairedAt: Date
    public var lastSeen: Date
    public init(id: String, name: String, model: String, pairedAt: Date, lastSeen: Date) {
        self.id = id; self.name = name; self.model = model; self.pairedAt = pairedAt; self.lastSeen = lastSeen
    }
}

/// Paired Macs. The key lives only in the Keychain under `fling.peer.<id>`; `peers.json` holds names and dates,
/// owner-only, and never any key material.
public final class FlingPairingStore: @unchecked Sendable {
    public static func account(for id: String) -> String { "fling.peer.\(id)" }

    private let keychain: KeychainStore
    private let file: URL
    private let lock = NSLock()
    private var records: [FlingPairedPeer]

    public init(keychain: KeychainStore, directory: URL) {
        self.keychain = keychain
        self.file = directory.appendingPathComponent("peers.json")
        if let data = try? Data(contentsOf: file), let loaded = try? Self.decoder().decode([FlingPairedPeer].self, from: data) {
            records = loaded
        } else {
            records = []
        }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]; e.dateEncodingStrategy = .secondsSince1970; return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d
    }

    private func saveLocked() {
        guard let data = try? Self.encoder().encode(records) else { return }
        FlingFiles.writePrivately(data, to: file)
    }

    public var peers: [FlingPairedPeer] { lock.lock(); defer { lock.unlock() }; return records }

    /// The key as 32 bytes, only when both the record and the Keychain item exist.
    public func psk(for id: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard records.contains(where: { $0.id == id }), let text = keychain.get(Self.account(for: id)) else { return nil }
        return Data(base64Encoded: text)
    }

    /// Every paired id with its key, for the transfer listener.
    public func pskTable() -> [String: Data] {
        var table: [String: Data] = [:]
        for peer in peers { if let key = psk(for: peer.id) { table[peer.id] = key } }
        return table
    }

    public func pairedNames() -> [String: String] {
        let table = pskTable()
        return Dictionary(uniqueKeysWithValues: peers.filter { table[$0.id] != nil }.map { ($0.id, $0.name) })
    }

    @discardableResult
    public func add(id: String, name: String, model: String, psk: Data, now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard keychain.set(psk.base64EncodedString(), for: Self.account(for: id)) else { return false }
        records.removeAll { $0.id == id }
        records.append(FlingPairedPeer(id: id, name: name, model: model, pairedAt: now, lastSeen: now))
        saveLocked()
        return true
    }

    /// Deletes the Keychain item first; if that fails the record stays, so the Mac still shows as paired.
    @discardableResult
    public func remove(id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard keychain.remove(Self.account(for: id)) else { return false }
        records.removeAll { $0.id == id }
        saveLocked()
        return true
    }

    public func touch(id: String, now: Date) {
        lock.lock(); defer { lock.unlock() }
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].lastSeen = now
        saveLocked()
    }
}

enum FlingFiles {
    /// Writes through a hidden temp file created with mode 0600, then renames over the target.
    @discardableResult
    static func writePrivately(_ data: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temp) } else { try fm.moveItem(at: temp, to: url) }
            return true
        } catch {
            try? fm.removeItem(at: temp)
            return false
        }
    }
}
