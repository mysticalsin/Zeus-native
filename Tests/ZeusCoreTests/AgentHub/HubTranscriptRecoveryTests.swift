import Foundation
import Testing
@testable import ZeusCore

@Suite("Hub transcript recovery")
struct HubTranscriptRecoveryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-hub-recover-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func aLineWithoutFailedStillLoads() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let line = UUID()
        let store = HubTranscriptStore(directory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let json = """
        {"id":"\(id.uuidString)","lines":[{"id":"\(line.uuidString)","role":"person","text":"kept"}],"status":"idle"}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("\(id.uuidString).json"))
        let loaded = try #require(store.load(id))
        #expect(loaded.lines.first?.text == "kept")
        #expect(loaded.lines.first?.failed == false)
        #expect(loaded.schema == HubTranscript.schemaVersion)
    }

    @Test func replacingAnUnreadableFileKeepsACopy() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("not-json".utf8)
        try original.write(to: root.appendingPathComponent("\(id.uuidString).json"))
        let store = HubTranscriptStore(directory: root)
        let transcript = HubTranscript(id: id, lines: [HubTranscriptLine(role: .person, text: "next")])
        try store.write(transcript)
        let copies = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("corrupt") }
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == original)
        #expect(store.load(id)?.lines.first?.text == "next")
    }
}
