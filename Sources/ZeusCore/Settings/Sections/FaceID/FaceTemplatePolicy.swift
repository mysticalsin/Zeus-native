import Foundation

public enum FaceKeyProtection: Equatable, Sendable {
    case keychainUserPresence
    case none
}

public struct FaceEnrollmentDraft: Equatable, Sendable {
    public var id: String
    public var name: String
    public var samples: [[Float]]
    public var image: Data?
    public var thumbnail: Data?

    public init(id: String, name: String, samples: [[Float]], image: Data?, thumbnail: Data?) {
        self.id = id
        self.name = name
        self.samples = samples
        self.image = image
        self.thumbnail = thumbnail
    }
}

public enum FaceTemplateError: Error, Equatable, Sendable {
    case imageRefused
    case unprotectedKey
    case emptySamples
}

/// Sealed template bytes. One `delete` drops them.
public struct FaceTemplateCabinet: Equatable, Sendable {
    public private(set) var sealed: Data?

    public init() {}

    public var isEmpty: Bool { sealed == nil }

    public mutating func store(_ sealed: Data) {
        self.sealed = sealed
    }

    public mutating func delete() {
        sealed = nil
    }
}

public enum FaceTemplatePolicy {
    /// Seals samples only. A frame, a crop, or a thumbnail is refused, and so is a key that is not held for user presence.
    public static func seal(_ draft: FaceEnrollmentDraft, key: Data, protection: FaceKeyProtection) throws -> Data {
        if draft.image != nil || draft.thumbnail != nil { throw FaceTemplateError.imageRefused }
        if protection != .keychainUserPresence || key.count != FaceVault.keyLength { throw FaceTemplateError.unprotectedKey }
        if draft.samples.isEmpty { throw FaceTemplateError.emptySamples }
        let record = FaceRecord(
            id: draft.id,
            name: draft.name,
            isEnabled: true,
            revision: 1,
            samples: draft.samples,
            threshold: FaceMatch.threshold(forSamples: draft.samples)
        )
        do {
            return try FaceVault.seal(FaceVaultContents(faces: [record]), key: key)
        } catch {
            throw FaceTemplateError.unprotectedKey
        }
    }

    public static func validateJSON(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let fields = object as? [String: Any] else { throw FaceTemplateError.imageRefused }
        let banned: Set<String> = ["image", "thumbnail", "jpeg", "png", "pixel"]
        if !banned.isDisjoint(with: Set(fields.keys)) { throw FaceTemplateError.imageRefused }
        guard fields["samples"] != nil else { throw FaceTemplateError.emptySamples }
    }
}
