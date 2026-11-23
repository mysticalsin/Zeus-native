// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): SecureFaceStore.swift, FaceEnrollmentStore.swift.
import Foundation
import ZeusCore

/// Face templates live in one data-protection keychain item (`face.presence.templates`). The item is
/// `WhenUnlockedThisDeviceOnly` with biometry for the current fingerprints, or the device passcode.
/// The system asks on save and on read. This store does not keep the template bytes.
///
/// Names for the card sit in `face-presence.meta` with the samples removed. An older sealed file
/// (`face-presence.enc` plus `face.presence.vaultKey`) is read, written into the new item, checked,
/// and only then deleted. A miss leaves that older copy where it was.
struct FaceVaultStore: Sendable {
    static let keyAccount = "face.presence.vaultKey"
    static let templateAccount = "face.presence.templates"
    static let fileName = "face-presence.enc"
    static let metaName = "face-presence.meta"
    static let protection = FaceTemplateStore.protection

    enum LoadResult: Equatable {
        /// No file and no template: nothing enrolled.
        case empty
        case faces([FaceRecord])
        /// The stored face cannot be read. It is left as it is.
        case unreadable
        /// Fingerprints changed. The template was removed. Enroll again.
        case reenrol
    }

    enum SaveResult: Equatable {
        case saved
        /// The stored face could not be read, so it was left as it is.
        case refusedUnreadable
        /// The prompt was cancelled or the write did not finish. Nothing new was kept.
        case failed
    }

    let url: URL
    let metaURL: URL
    private let keychain: KeychainStore
    private let templates: any FaceTemplateKeychain
    private var templateStore: FaceTemplateStore {
        FaceTemplateStore(keychain: templates, account: Self.templateAccount, protection: Self.protection)
    }

    /// `directory` is Zeus's support folder by default; tests pass a temp folder.
    init(directory: URL = ZeusPaths.supportDirectory, keychain: KeychainStore = Keychain.store,
         templates: any FaceTemplateKeychain = SystemFaceTemplateKeychain()) {
        self.url = directory.appendingPathComponent(Self.fileName)
        self.metaURL = directory.appendingPathComponent(Self.metaName)
        self.keychain = keychain
        self.templates = templates
    }

    func load() -> LoadResult {
        if templates.protection(of: Self.templateAccount) != nil {
            if FileManager.default.fileExists(atPath: url.path), keychain.get(Self.keyAccount) == nil {
                try? FileManager.default.removeItem(at: url)
            }
            return readMeta()
        }
        if FileManager.default.fileExists(atPath: url.path) {
            switch migrate() {
            case .success: return readMeta()
            case .failure(.biometryChanged): return .reenrol
            case .failure: return .unreadable
            }
        }
        if FileManager.default.fileExists(atPath: metaURL.path) { return .unreadable }
        return .empty
    }

    /// Stores exactly `faces`. An empty list removes the template and the meta file. Refuses when
    /// the stored face cannot be read. A cancelled prompt stores nothing.
    func save(_ faces: [FaceRecord]) -> SaveResult {
        if load() == .unreadable { return .refusedUnreadable }
        guard !faces.isEmpty else { return erase() ? .saved : .failed }
        let stored: [FaceRecord]
        if faces.contains(where: { $0.samples.isEmpty }) {
            switch storedTemplates() {
            case .success(let records): stored = records
            case .failure: return .failed
            }
        } else {
            stored = []
        }
        let merged = faces.map { face in
            guard face.samples.isEmpty, let prior = stored.first(where: { $0.id == face.id }), !prior.samples.isEmpty else { return face }
            return FaceRecord(id: face.id, name: face.name, isEnabled: face.isEnabled, revision: prior.revision,
                              samples: prior.samples, threshold: prior.threshold)
        }
        guard let payload = Self.payload(FaceVaultContents(faces: merged)) else { return .failed }
        switch templateStore.save(payload, identity: "") {
        case .success: break
        case .failure: return .failed
        }
        var matched = false
        let verified = templateStore.withTemplate(identity: "") { matched = $0 == payload }
        guard case .success = verified, matched else {
            _ = templates.remove(account: Self.templateAccount)
            return .failed
        }
        guard writeMeta(faces) else {
            _ = templates.remove(account: Self.templateAccount)
            return .failed
        }
        return .saved
    }

    private func storedTemplates() -> Result<[FaceRecord], FaceTemplateFailure> {
        var records: [FaceRecord] = []
        let result = withTemplates { records = $0 }
        switch result {
        case .success: return .success(records)
        case .failure(let error): return .failure(error)
        }
    }

    /// The samples for one match. They are not kept after `body` returns. Cancel and failure do
    /// not call `body`.
    func withTemplates(_ body: ([FaceRecord]) -> Void) -> Result<Void, FaceTemplateFailure> {
        var faces: [FaceRecord] = []
        var decodeFailed = false
        let result = templateStore.withTemplate(identity: "") { data in
            if let contents = try? JSONDecoder().decode(FaceVaultContents.self, from: data),
               contents.version == FaceVaultContents.currentVersion {
                faces = contents.faces
            } else {
                decodeFailed = true
            }
        }
        switch result {
        case .failure(let error): return .failure(error)
        case .success where decodeFailed: return .failure(.unavailable)
        case .success:
            body(faces)
            return .success(())
        }
    }

    /// Removes the meta file, a leftover sealed file, the template and the old key.
    @discardableResult
    func erase() -> Bool {
        let manager = FileManager.default
        for file in [url, metaURL] where manager.fileExists(atPath: file.path) {
            do { try manager.removeItem(at: file) } catch { return false }
        }
        guard case .success = templates.remove(account: Self.templateAccount) else { return false }
        return keychain.remove(Self.keyAccount)
    }

    private func migrate() -> Result<Void, FaceTemplateFailure> {
        guard let bytes = try? Data(contentsOf: url),
              let key = keychain.get(Self.keyAccount).flatMap({ FaceVault.key(fromBase64: $0) }),
              let contents = try? FaceVault.open(bytes, key: key),
              let payload = Self.payload(contents) else { return .failure(.unavailable) }
        let outcome = FaceTemplateMigration.run(
            readOld: { .success(payload) },
            writeNew: { templateStore.save($0, identity: "") },
            readNew: {
                var copy = Data()
                switch templateStore.withTemplate(identity: "") { copy = $0 } {
                case .success: return .success(copy)
                case .failure(let error): return .failure(error)
                }
            },
            deleteNew: { templates.remove(account: Self.templateAccount) },
            deleteOld: {
                guard writeMeta(contents.faces) else {
                    _ = templates.remove(account: Self.templateAccount)
                    return .failure(.unavailable)
                }
                return deleteOld()
            })
        return outcome
    }

    private func deleteOld() -> Result<Void, FaceTemplateFailure> {
        guard keychain.remove(Self.keyAccount) else { return .failure(.unavailable) }
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch { return .failure(.unavailable) }
        }
        return .success(())
    }

    private func readMeta() -> LoadResult {
        guard let bytes = try? Data(contentsOf: metaURL),
              let contents = try? JSONDecoder().decode(FaceVaultContents.self, from: bytes),
              contents.version == FaceVaultContents.currentVersion else { return .unreadable }
        let faces = contents.faces.map { $0.withoutSamples() }
        return faces.isEmpty ? .empty : .faces(faces)
    }

    private func writeMeta(_ faces: [FaceRecord]) -> Bool {
        let bare = faces.map { $0.withoutSamples() }
        guard let data = Self.payload(FaceVaultContents(faces: bare)) else { return false }
        let manager = FileManager.default
        let directory = metaURL.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        } catch { return false }
        let temp = directory.appendingPathComponent(".face-presence-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        guard rename(temp.path, metaURL.path) == 0 else {
            try? manager.removeItem(at: temp)
            return false
        }
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metaURL.path)
        return true
    }

    private static func payload(_ contents: FaceVaultContents) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(contents)
    }
}
