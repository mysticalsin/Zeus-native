// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): SecureFaceStore.swift, FaceEnrollmentStore.swift.
import Foundation
import ZeusCore

/// The file and the key of the face vault. The file is `face-presence.enc` in Zeus's support folder, sealed with
/// AES-GCM (`FaceVault`); the key is 32 random bytes kept through `KeychainStore`. Embeddings only, never an image.
///
/// A file that cannot be read (missing key, wrong key, damaged, newer format) is `unreadable`, never `empty`, and a
/// save never writes over it. The vault is not shared with the login: there is no secret here but the key.
struct FaceVaultStore: Sendable {
    static let keyAccount = "face.presence.vaultKey"
    static let fileName = "face-presence.enc"

    enum LoadResult: Equatable {
        /// No file: nothing enrolled.
        case empty
        case faces([FaceRecord])
        case unreadable
        /// The caller did not bring a confirmed proof for a read, so the file stayed closed.
        case needsPresence
    }

    enum SaveResult: Equatable {
        case saved
        /// The stored file could not be read, so it was left as it is.
        case refusedUnreadable
        /// The caller did not bring a confirmed proof for a save, so nothing was written.
        case needsPresence
        /// The key or the file could not be written. Nothing the owner can open was left behind.
        case failed
    }

    let url: URL
    private let keychain: KeychainStore

    /// `directory` is Zeus's support folder by default; tests pass a temp folder.
    init(directory: URL = ZeusPaths.supportDirectory, keychain: KeychainStore = Keychain.store) {
        self.url = directory.appendingPathComponent(Self.fileName)
        self.keychain = keychain
    }

    func load(presence: FaceTemplateProof) -> LoadResult {
        guard presence.allows(.read) else { return .needsPresence }
        return read()
    }

    private func read() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let bytes = try? Data(contentsOf: url),
              let key = keychain.get(Self.keyAccount).flatMap({ FaceVault.key(fromBase64: $0) }),
              let contents = try? FaceVault.open(bytes, key: key)
        else { return .unreadable }
        return contents.faces.isEmpty ? .empty : .faces(contents.faces)
    }

    /// Stores exactly `faces`. An empty list removes the file and the key. Refuses when the stored vault is unreadable.
    /// A proof for a read, or a proof that the person was not present, leaves the file and the key as they were.
    func save(_ faces: [FaceRecord], presence: FaceTemplateProof) -> SaveResult {
        guard presence.allows(.save) else { return .needsPresence }
        if read() == .unreadable { return .refusedUnreadable }
        guard !faces.isEmpty else { return erase(presence: presence) ? .saved : .failed }
        let key: Data
        if let stored = keychain.get(Self.keyAccount).flatMap({ FaceVault.key(fromBase64: $0) }) {
            key = stored
        } else {
            // The key goes in first, so a file never exists without it. Reaching here with a file present is
            // impossible: `load` called that unreadable.
            key = FaceVault.makeKey()
            guard keychain.set(key.base64EncodedString(), for: Self.keyAccount) else { return .failed }
        }
        guard let sealed = try? FaceVault.seal(FaceVaultContents(faces: faces), key: key), write(sealed) else {
            return .failed
        }
        return .saved
    }

    /// Removes the file, then the key. The only way out of an unreadable vault, and only when a confirmed
    /// save proof says the person is here. A read proof or an absent person leaves both in place.
    /// True when both are gone afterwards.
    @discardableResult
    func erase(presence: FaceTemplateProof) -> Bool {
        guard presence.allowsErase else { return false }
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            do { try manager.removeItem(at: url) } catch { return false }
        }
        return keychain.remove(Self.keyAccount)
    }

    /// A private temp file in the same folder, renamed over the target, so the vault is never half written and never
    /// readable by others, even briefly.
    private func write(_ data: Data) -> Bool {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch { return false }
        let temp = directory.appendingPathComponent(".face-presence-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        guard rename(temp.path, url.path) == 0 else {
            try? manager.removeItem(at: temp)
            return false
        }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
}
