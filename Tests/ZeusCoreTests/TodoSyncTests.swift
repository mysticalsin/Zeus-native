import Foundation
import Testing
@testable import ZeusCore

/// Every write test uses a throwaway vault in the temp folder, never a real one.
@Suite("To-do sync")
struct TodoSyncTests {
    private func tempVault() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-todo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        return root
    }

    private func connection(_ vault: URL, _ access: BrainConnection.Access, _ target: BrainConnection.TodoTarget) -> BrainConnection {
        BrainConnection(source: BrainSource(kind: .obsidian, name: "Test", path: vault.path), access: access, todo: target)
    }

    @Test func writesAndReadsTheNote() throws {
        let vault = try tempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let note = vault.appendingPathComponent("ZEUS/To-do.md")
        var sync = TodoSync(storeFile: vault.appendingPathComponent("store.json"),
                            connection: connection(vault, .readWrite, .note(BrainConnection.defaultTodoNote)))
        sync.list.add("Call Anna", due: "2026-11-02")
        try sync.commit()
        #expect(try String(contentsOf: note, encoding: .utf8).contains("- [ ] Call Anna 📅 2026-11-02"))

        // Edited in Obsidian: checked off, and a new task typed in.
        Thread.sleep(forTimeInterval: 1.1)
        try "## To-do\n- [x] Call Anna 📅 2026-11-02\n- [ ] Buy milk\n".write(to: note, atomically: true, encoding: .utf8)
        let id = sync.list.items[0].id
        let changed = sync.pull()
        #expect(changed)
        #expect(sync.list.items.map(\.title) == ["Call Anna", "Buy milk"])
        #expect(sync.list.items[0].done && sync.list.items[0].id == id)

        // ZEUS's own copy survives a relaunch.
        let reopened = TodoSync(storeFile: vault.appendingPathComponent("store.json"))
        #expect(reopened.list.items.count == 2)
    }

    @Test func readOnlyNeverWrites() throws {
        let vault = try tempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        var sync = TodoSync(storeFile: vault.appendingPathComponent("store.json"),
                            connection: connection(vault, .readOnly, .note(BrainConnection.defaultTodoNote)))
        sync.list.add("Stay local")
        try sync.commit()
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("ZEUS/To-do.md").path))
        #expect(sync.noteURL() == nil)
    }

    @Test func refusesNotesOutsideTheVault() throws {
        let vault = try tempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let sync = TodoSync(storeFile: vault.appendingPathComponent("store.json"),
                            connection: connection(vault, .readWrite, .note("../escape.md")))
        #expect(sync.noteURL() == nil)
    }
}
