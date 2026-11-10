import Foundation
import Testing
import ZeusCore
@testable import Zeus

@MainActor @Suite("Save to Brain preview")
struct BrainCaptureModelTests {
    private func fixture() throws -> (URL, BrainConnection) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-capture-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let selected = BrainConnection(source: .init(kind: .markdown, name: "Fixture", path: root.path), access: .readWrite)
        return (root, selected)
    }

    @Test func previewIsStableAndSaveWritesOnlyAfterTheExplicitAction() throws {
        let (root, selected) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BrainCaptureModel(title: "Meeting", body: "Selected text", source: "chat", currentConnection: { selected })
        let target = try #require(model.target)
        let preview = model.preview
        #expect(!FileManager.default.fileExists(atPath: target.path))
        model.save()
        #expect(model.saved == target)
        #expect(try String(contentsOf: target, encoding: .utf8) == preview)
    }

    @Test func accessRevokedWhilePreviewIsOpenBlocksSave() throws {
        let (root, selected) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = selected
        let model = BrainCaptureModel(title: "Review", body: "Private", source: "chat", currentConnection: { current })
        let target = try #require(model.target)
        current.access = .readOnly
        model.save()
        #expect(model.saved == nil)
        #expect(model.problem != nil)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func aClaimedPreviewFilenameIsNotOverwrittenOrSilentlyChanged() throws {
        let (root, selected) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BrainCaptureModel(title: "Review", body: "Private", source: "chat", currentConnection: { selected })
        let target = try #require(model.target)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Existing note".write(to: target, atomically: true, encoding: .utf8)
        model.save()
        #expect(model.saved == nil)
        #expect(model.problem != nil)
        #expect(model.target == target)
        #expect(try String(contentsOf: target, encoding: .utf8) == "Existing note")
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).count == 1)
    }
}
