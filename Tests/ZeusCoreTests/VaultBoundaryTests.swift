import Foundation
import Testing
@testable import ZeusCore

@Suite("Vault boundaries and selected capture")
struct VaultBoundaryTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-vault-boundary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func folder(_ root: URL, _ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func connection(_ vault: URL) -> BrainConnection {
        BrainConnection(source: .init(kind: .obsidian, name: "Chosen", path: vault.path),
                        access: .readWrite, todo: .note(BrainConnection.defaultTodoNote))
    }

    @Test func profileCannotWriteThroughLinkedInbox() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        let outside = try folder(root, "outside")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("00_Inbox"), withDestinationURL: outside)
        let target = ProfileNoteWriter.folder(in: vault).appendingPathComponent("note.md")
        #expect(throws: ProfileNoteWriter.WriteError.outsideVault) {
            try ProfileNoteWriter.write("private note", to: target, vault: vault)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func writeScopeRejectsLinkedNotesAndFoldersIncludingDanglingLinks() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        _ = try folder(vault, "ZEUS")
        let outside = try folder(root, "outside")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("ZEUS/To-do.md"),
                                                  withDestinationURL: outside.appendingPathComponent("missing.md"))
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("ZEUS/Inbox"), withDestinationURL: outside)
        let selected = connection(vault)
        #expect(selected.todoURL() == nil)
        #expect(!selected.mayWrite(vault.appendingPathComponent("ZEUS/To-do.md")))
        #expect(!selected.mayWrite(vault.appendingPathComponent("ZEUS/Inbox/new.md")))
        #expect(!selected.mayWrite(URL(string: "https://example.com/ZEUS/Inbox/new.md")!))
        #expect(BrainCapture.plannedURL(connection: selected, title: "Test", created: Date()) == nil)
    }

    @Test func aliasesInsideTheVaultCannotBroadenTheInboxScope() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        _ = try folder(vault, "ZEUS")
        let projects = try folder(vault, "Projects")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("ZEUS/Inbox"), withDestinationURL: projects)
        #expect(!connection(vault).mayWrite(vault.appendingPathComponent("ZEUS/Inbox/plan.md")))
    }

    @Test func dotSegmentsCannotHideAReadOrWriteThroughASymlink() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        let external = try folder(root, "outside/child")
        _ = try folder(vault, "00_Inbox/from-zeus")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("00_Inbox/from-zeus/link"),
                                                  withDestinationURL: external)
        let target = vault.appendingPathComponent("00_Inbox/from-zeus/link/../escaped.md")
        #expect(VaultPathBoundary.relativePath(of: target, in: vault) == nil)
        #expect(throws: ProfileNoteWriter.WriteError.outsideVault) {
            try ProfileNoteWriter.write("private", to: target, vault: vault)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside/escaped.md").path))
    }

    @Test func explicitlyChosenRootMayBeAnAlias() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        let alias = root.appendingPathComponent("chosen-vault")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: vault)
        let selected = connection(alias)
        let target = try #require(BrainCapture.plannedURL(connection: selected, title: "Test", created: Date()))
        try BrainCapture.write("selected", to: target, connection: selected)
        #expect(try String(contentsOf: target, encoding: .utf8) == "selected")
    }

    @Test func allVaultReadersSkipExternalMarkdownLinks() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        let outside = root.appendingPathComponent("outside.md")
        try "# Private\n- [ ] UniqueSecret 📅 2026-01-01\n".write(to: outside, atomically: true, encoding: .utf8)
        let linked = vault.appendingPathComponent("Meeting 2026-01-01.md")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        #expect(BrainRecall.search(vault: vault, topic: "UniqueSecret").isEmpty)
        #expect(BrainToday.scan(root: vault).isEmpty)
        let summary = TodayScanner.scan(vault: vault, daily: .init(format: "[Meeting 2026-01-01]"))
        #expect(summary.tasks.isEmpty)
        #expect(summary.meetings.isEmpty)
        #expect(summary.dailyNote == nil)
    }

    @Test func configuredDestinationAndReadOnlySettingNeverFallBack() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let chosen = try folder(root, "selected")
        let legacy = try folder(root, "legacy")
        var configured = connection(chosen)
        configured.access = .readOnly
        let selected = try #require(BrainCapture.connection(configured: configured, legacyVault: legacy))
        #expect(selected == configured)
        #expect(BrainCapture.plannedURL(connection: selected, title: "Private", created: Date()) == nil)
        #expect(BrainCapture.connection(configured: nil, legacyVault: nil) == nil)
        let implicit = try folder(root, "Documents/brain/.obsidian")
        #expect(FileManager.default.fileExists(atPath: implicit.path))
        #expect(BrainCapture.vault(saved: nil, home: root) == nil)
        #expect(BrainCapture.vault(saved: root.appendingPathComponent("missing"), home: root) == nil)
    }

    @Test func captureUsesChosenInboxAndNeverOverwritesOrWritesElsewhere() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var selected = connection(root)
        selected.inboxFolder = "Selected/Inbox"
        let target = try #require(BrainCapture.plannedURL(connection: selected, title: "Review", created: Date()))
        #expect(target.deletingLastPathComponent().path == root.appendingPathComponent("Selected/Inbox").path)
        try BrainCapture.write("first", to: target, connection: selected)
        #expect(throws: (any Error).self) { try BrainCapture.write("second", to: target, connection: selected) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "first")
        #expect(throws: BrainCapture.WriteError.unavailableDestination) {
            try BrainCapture.write("no", to: root.appendingPathComponent(BrainConnection.defaultTodoNote), connection: selected)
        }
    }

    @Test func captureChecksScopeAgainWhenThePreviewIsSaved() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try folder(root, "vault")
        _ = try folder(vault, "ZEUS")
        let outside = try folder(root, "outside")
        let selected = connection(vault)
        let target = try #require(BrainCapture.plannedURL(connection: selected, title: "Review", created: Date()))
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("ZEUS/Inbox"), withDestinationURL: outside)
        #expect(throws: BrainCapture.WriteError.unavailableDestination) {
            try BrainCapture.write("no", to: target, connection: selected)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
