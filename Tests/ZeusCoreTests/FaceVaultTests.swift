import Foundation
import Testing
@testable import ZeusCore

@Suite("Face vault")
struct FaceVaultTests {
    static let samples: [[Float]] = [
        [0.5, -0.25, 0.125, 0.0625, 0.3, 0.7, -0.9, 0.11],
        [0.4, -0.35, 0.225, 0.1625, 0.2, 0.6, -0.8, 0.21],
    ]

    static func record(id: String = "face-1", name: String = "Face 1", enabled: Bool = true) -> FaceRecord {
        FaceRecord(id: id, name: name, isEnabled: enabled, revision: 2, samples: samples, threshold: 0.31)
    }

    static func contents(_ faces: [FaceRecord] = [record()]) -> FaceVaultContents {
        FaceVaultContents(faces: faces)
    }

    @Test func sealOpenRoundTrip() throws {
        let key = FaceVault.makeKey()
        #expect(key.count == 32)
        let original = Self.contents([Self.record(), Self.record(id: "face-2", name: "Face 2", enabled: false)])
        let sealed = try FaceVault.seal(original, key: key)
        let opened = try FaceVault.open(sealed, key: key)
        #expect(opened == original)
        #expect(opened.version == FaceVaultContents.currentVersion)
        // Sealing twice gives different bytes (a fresh nonce each time), and both open.
        let again = try FaceVault.seal(original, key: key)
        #expect(again != sealed)
        #expect(try FaceVault.open(again, key: key) == original)
    }

    @Test func sealedFileHoldsNoPlaintextEmbedding() throws {
        let key = FaceVault.makeKey()
        let sealed = try FaceVault.seal(Self.contents(), key: key)
        // Neither the raw float bytes of a sample, nor the JSON field names, nor the face name appear in the file.
        for sample in Self.samples {
            let raw = sample.withUnsafeBytes { Data($0) }
            #expect(sealed.range(of: raw) == nil)
        }
        for text in ["samples", "threshold", "Face 1", "isEnabled", "0.3125", "revision", "\"id\""] {
            #expect(sealed.range(of: Data(text.utf8)) == nil, "found \(text)")
        }
        // The same record sealed in the clear would hold them, so the check above is not empty.
        let clear = try JSONEncoder().encode(Self.contents())
        #expect(clear.range(of: Data("samples".utf8)) != nil)
    }

    @Test func aWrongKeyFailsToOpen() throws {
        let sealed = try FaceVault.seal(Self.contents(), key: FaceVault.makeKey())
        #expect(throws: FaceVaultError.self) { try FaceVault.open(sealed, key: FaceVault.makeKey()) }
        // A key of the wrong length is refused, not padded.
        #expect(throws: FaceVaultError.self) { try FaceVault.open(sealed, key: Data(repeating: 1, count: 16)) }
        #expect(throws: FaceVaultError.self) { try FaceVault.seal(Self.contents(), key: Data(repeating: 1, count: 16)) }
    }

    @Test func aChangedFileFailsToOpen() throws {
        let key = FaceVault.makeKey()
        var sealed = try FaceVault.seal(Self.contents(), key: key)
        // Flip one bit in the middle of the sealed bytes: the tag no longer matches.
        sealed[sealed.count / 2] ^= 0x01
        #expect(throws: FaceVaultError.self) { try FaceVault.open(sealed, key: key) }
        #expect(throws: FaceVaultError.self) { try FaceVault.open(Data(), key: key) }
        #expect(throws: FaceVaultError.self) { try FaceVault.open(Data("not a vault".utf8), key: key) }
    }

    @Test func aNewerFormatIsUnreadableNotEmpty() throws {
        let key = FaceVault.makeKey()
        let newer = FaceVaultContents(version: FaceVaultContents.currentVersion + 1, faces: [Self.record()])
        let sealed = try FaceVault.seal(newer, key: key)
        #expect(throws: FaceVaultError.self) { try FaceVault.open(sealed, key: key) }
    }

    @Test func aMissingEnabledFlagDecodesAsEnabled() throws {
        let json = """
        {"id":"a","name":"Face 1","revision":2,"samples":[[1,0,0],[0,1,0]],"threshold":0.3}
        """
        let decoded = try JSONDecoder().decode(FaceRecord.self, from: Data(json.utf8))
        #expect(decoded.isEnabled)
        let off = """
        {"id":"a","name":"Face 1","isEnabled":false,"revision":2,"samples":[[1,0,0]],"threshold":0.3}
        """
        #expect(try JSONDecoder().decode(FaceRecord.self, from: Data(off.utf8)).isEnabled == false)
    }

    @Test func recordsHoldNoImageField() throws {
        let data = try JSONEncoder().encode(Self.record())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "name", "isEnabled", "revision", "samples", "threshold"])
        // Every stored value is text, a number, a flag or a list of numbers: no data blob that could hold pixels.
        #expect(object["samples"] is [[Double]])
        let labels = Mirror(reflecting: Self.record()).children.compactMap(\.label)
        #expect(Set(labels) == ["id", "name", "isEnabled", "revision", "samples", "threshold"])
        let contentLabels = Mirror(reflecting: Self.contents()).children.compactMap(\.label)
        #expect(Set(contentLabels) == ["version", "faces"])
    }

    @Test func aRecordBecomesAnEnrolledFaceOfTheSameValues() {
        let face = Self.record(enabled: false).enrolledFace
        #expect(face.id == "face-1")
        #expect(face.name == "Face 1")
        #expect(!face.isEnabled)
        #expect(face.revision == 2)
        #expect(face.threshold == 0.31)
        #expect(face.samples.count == 2)
        #expect(!face.centroid.isEmpty)
    }

    @Test func theKeyTravelsAsBase64OfExactlyThirtyTwoBytes() {
        let key = FaceVault.makeKey()
        #expect(FaceVault.key(fromBase64: key.base64EncodedString()) == key)
        #expect(FaceVault.key(fromBase64: Data(repeating: 7, count: 31).base64EncodedString()) == nil)
        #expect(FaceVault.key(fromBase64: "not base64 !!") == nil)
        #expect(FaceVault.key(fromBase64: "") == nil)
    }
}
