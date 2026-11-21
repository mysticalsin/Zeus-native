// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): SecureFaceStore.swift, FaceEnrollmentStore.swift.
import CryptoKit
import Foundation

/// One enrolled face as it is stored: numbers and text only. There is no image, crop or thumbnail field, and the
/// vault tests keep it that way.
public struct FaceRecord: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// A switched off face is kept and never matched. A record written without the flag reads as enabled.
    public let isEnabled: Bool
    public let revision: Int
    /// Feature print vectors of the accepted enrollment samples.
    public let samples: [[Float]]
    public let threshold: Float

    public init(id: String, name: String, isEnabled: Bool, revision: Int, samples: [[Float]], threshold: Float) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.revision = revision
        self.samples = samples
        self.threshold = threshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        revision = try container.decode(Int.self, forKey: .revision)
        samples = try container.decode([[Float]].self, forKey: .samples)
        threshold = try container.decode(Float.self, forKey: .threshold)
    }

    /// The matcher's view of this record.
    public var enrolledFace: EnrolledFace {
        EnrolledFace(id: id, name: name, isEnabled: isEnabled, revision: revision, samples: samples, threshold: threshold)
    }

    public func with(isEnabled: Bool) -> FaceRecord {
        FaceRecord(id: id, name: name, isEnabled: isEnabled, revision: revision, samples: samples, threshold: threshold)
    }

    /// The row the card keeps. The samples stay in the protected keychain item, not on this copy.
    public func withoutSamples() -> FaceRecord {
        FaceRecord(id: id, name: name, isEnabled: isEnabled, revision: revision, samples: [], threshold: threshold)
    }
}

/// Everything the vault file holds.
public struct FaceVaultContents: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let faces: [FaceRecord]

    public init(version: Int = FaceVaultContents.currentVersion, faces: [FaceRecord]) {
        self.version = version
        self.faces = faces
    }
}

public enum FaceVaultError: Error, Equatable, Sendable {
    /// The key is not 32 bytes, the bytes are not a sealed vault, the key does not open them, or they were changed.
    case unreadable
    /// The file was written by a format this build does not know. Never read as empty.
    case unsupportedVersion
    case sealFailed
}

/// Sealing and opening of the vault bytes with AES-GCM. Pure: no file, no Keychain. An edited or foreign file fails
/// to open and is the caller's "unreadable", never "empty".
public enum FaceVault {
    public static let keyLength = 32
    /// Bound into the tag, so bytes sealed for something else under the same key do not open as a vault.
    static let context = Data("zeus.face-presence.vault.v1".utf8)

    /// 32 random bytes from the system generator.
    public static func makeKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// The key from its Keychain text (base64), or nil when it is not exactly 32 bytes.
    public static func key(fromBase64 text: String) -> Data? {
        guard let data = Data(base64Encoded: text), data.count == keyLength else { return nil }
        return data
    }

    public static func seal(_ contents: FaceVaultContents, key: Data) throws -> Data {
        guard key.count == keyLength else { throw FaceVaultError.unreadable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let plain = try? encoder.encode(contents),
              let box = try? AES.GCM.seal(plain, using: SymmetricKey(data: key), authenticating: context),
              let combined = box.combined
        else { throw FaceVaultError.sealFailed }
        return combined
    }

    public static func open(_ sealed: Data, key: Data) throws -> FaceVaultContents {
        guard key.count == keyLength else { throw FaceVaultError.unreadable }
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: context),
              let contents = try? JSONDecoder().decode(FaceVaultContents.self, from: plain)
        else { throw FaceVaultError.unreadable }
        guard contents.version == FaceVaultContents.currentVersion else { throw FaceVaultError.unsupportedVersion }
        return contents
    }
}
