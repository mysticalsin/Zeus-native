import Foundation
import Testing
@testable import ZeusCore

@Suite("Damaged memory is not empty")
struct DamagedMemoryTests {
    @Test func userMemoryPromptReportsDamageAndKeepsTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s06-user-mem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("user-memory.json")
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)
        let persistence = UserMemoryPersistence(url: url)
        let read = persistence.promptRead(for: "what do you remember")
        #expect(read.damaged)
        #expect(read.text == UserMemoryPersistence.PromptRead.damagedNotice)
        #expect(try Data(contentsOf: url) == garbage)
        #expect(throws: UserMemoryError.self) { try persistence.save(UserMemoryStore()) }
    }

    @Test func agentMemoryIsQuarantinedAndNotReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s06-agent-mem-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentStore(root: root)
        let agent = AgentProfile(name: "Scout", role: "research", instructions: "facts")
        let url = root.appendingPathComponent("\(agent.slug).memory.json")
        let garbage = Data("{".utf8)
        try garbage.write(to: url)
        let loaded = store.loadMemory(for: agent)
        #expect(loaded == .damaged(AgentStore.MemoryLoad.notice))
        var fresh = AgentMemory()
        fresh.remember("only the new note", pinned: true)
        #expect(throws: AgentStore.MemoryError.self) { try store.save(fresh, for: agent) }
        #expect(try Data(contentsOf: url) == garbage)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }
}
