import Foundation
import Testing
@testable import ZeusCore

@Suite("W7 to-do sync and tab-row repair")
struct W7TodoTodayTests {
    private func makeVault() throws -> (root: URL, note: URL, store: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("w7-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("vault/ZEUS", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        return (root, notes.appendingPathComponent("To-do.md"), root.appendingPathComponent("support/todos.json"))
    }

    private func connection(_ root: URL) -> BrainConnection {
        let source = BrainSource(kind: .markdown, name: "Vault", path: root.appendingPathComponent("vault").path)
        return BrainConnection(source: source, access: .readWrite, todo: .note(BrainConnection.defaultTodoNote))
    }

    @Test func unreadableNoteIsNeverOverwritten() throws {
        let paths = try makeVault()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bytes = Data([0xFF, 0xFE, 0xFA, 0x80])
        try bytes.write(to: paths.note)
        var sync = TodoSync(storeFile: paths.store, connection: connection(paths.root))
        _ = sync.list.add("write report", due: nil)
        var threw = false
        do { try sync.commit() } catch { threw = true }
        #expect(threw)
        #expect(sync.syncError != nil)
        #expect((try? Data(contentsOf: paths.note)) == bytes)
    }

    @Test func missingNoteIsCreated() throws {
        let paths = try makeVault()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var sync = TodoSync(storeFile: paths.store, connection: connection(paths.root))
        _ = sync.list.add("first task", due: nil)
        try sync.commit()
        let text = try String(contentsOf: paths.note, encoding: .utf8)
        #expect(text.contains("first task"))
        #expect(sync.syncError == nil)
    }

    @Test func unreadableNoteOnPullIsReportedAndRetried() throws {
        let paths = try makeVault()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try Data([0xFF, 0xFE, 0xFA]).write(to: paths.note)
        var sync = TodoSync(storeFile: paths.store, connection: connection(paths.root))
        let changed = sync.pull()
        #expect(!changed)
        #expect(sync.list.items.isEmpty)
        #expect(sync.syncError != nil)
        // The stamp stays unseen, so the next tick looks again.
        #expect(sync.noteMayHaveChanged())
    }

    @Test func pullSaveFailureIsKeptForRetry() throws {
        let paths = try makeVault()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        // The store's folder is a regular file, so the save cannot succeed.
        let blocker = paths.root.appendingPathComponent("support")
        try Data("x".utf8).write(to: blocker)
        try "- [ ] from the note\n".write(to: paths.note, atomically: true, encoding: .utf8)
        var sync = TodoSync(storeFile: paths.store, connection: connection(paths.root))
        let changed = sync.pull()
        #expect(changed)
        #expect(sync.pendingSave)
        #expect(sync.saveError != nil)
        #expect(sync.noteMayHaveChanged())
        // Once the folder can be written, the next pull saves and clears the retry.
        try FileManager.default.removeItem(at: blocker)
        _ = sync.pull()
        #expect(!sync.pendingSave)
        #expect(sync.saveError == nil)
        #expect(FileManager.default.fileExists(atPath: paths.store.path))
    }

    @Test func repairAddsTabsNeverOfferedAndIsIdempotent() {
        let old = TopBarLayout(tabs: TopBarLayout.glanceSeven)
        let once = TopBarLayoutRepair.repaired(old, savedKnown: nil)
        for tab in TopBarLayoutRepair.upgradeTabs { #expect(once.contains(tab)) }
        #expect(TopBarLayoutRepair.repaired(once, savedKnown: nil) == once)
        #expect(Array(once.tabs.prefix(TopBarLayout.defaultRow.count)) == TopBarLayout.defaultRow)
    }

    @Test func repairKeepsTabsThePersonTurnedOff() {
        let layout = TopBarLayout(tabs: TopBarLayout.glanceSeven + [.teleprompter])
        let known = TopBarLayout.knownEncoded()
        #expect(TopBarLayoutRepair.repaired(layout, savedKnown: known) == layout)
        let oldKnown = "[\"home\",\"polyglot\"]"
        let repaired = TopBarLayoutRepair.repaired(layout, savedKnown: oldKnown)
        #expect(!repaired.contains(.polyglot))
        #expect(repaired.contains(.insomnia))
    }
}
