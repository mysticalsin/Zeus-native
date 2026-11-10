import Foundation
import Testing
@testable import ZeusCore

@Suite("About you")
struct AboutYouTests {
    /// Every test works in its own temp folder; the real ~/Documents/brain is never touched.
    func tempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-about-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func note(_ url: URL, _ text: String = "x") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func detectsBrainOnlyWhenItLooksLikeAVault() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(SecondBrain.detect(home: home) == nil)
        let brain = home.appendingPathComponent("Documents/brain")
        try FileManager.default.createDirectory(at: brain, withIntermediateDirectories: true)
        #expect(SecondBrain.detect(home: home) == nil) // empty folder
        try note(brain.appendingPathComponent("10_Projects/zeus.md"))
        #expect(SecondBrain.detect(home: home)?.lastPathComponent == "brain")
        let obsidian = home.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: obsidian.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        #expect(SecondBrain.looksLikeVault(obsidian))
    }

    @Test func summaryCountsNotesAndFolders() throws {
        let vault = try tempHome()
        defer { try? FileManager.default.removeItem(at: vault) }
        try note(vault.appendingPathComponent("10_Projects/a.md"))
        try note(vault.appendingPathComponent("10_Projects/b.md"))
        try note(vault.appendingPathComponent("20_Areas/c.md"))
        try note(vault.appendingPathComponent("root.md"))
        try note(vault.appendingPathComponent(".obsidian/hidden.md"))
        try note(vault.appendingPathComponent("10_Projects/image.png"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("00_Inbox"), withIntermediateDirectories: true)
        let summary = SecondBrain.summarize(vault)
        #expect(summary.notes == 4)
        #expect(summary.folders == ["10_Projects", "20_Areas"])
        #expect(summary.hasInbox && !summary.truncated)
        #expect(SecondBrain.summarize(vault, cap: 2).truncated)
    }

    @Test func profileMarkdown() {
        let profile = AboutYouProfile(name: " Tony ", work: "Builds ZEUS", helpWith: "Mornings and email", notes: "")
        #expect(profile.isComplete)
        #expect(!AboutYouProfile(name: "  ").isComplete)
        let text = profile.markdown(created: Date(timeIntervalSince1970: 1_793_475_612),
                                    vaultSummary: .init(notes: 120, folders: ["10_Projects", "20_Areas"], hasInbox: true, truncated: false),
                                    timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.hasPrefix("---\ntype: profile\nsource: zeus\ncreated: 2026-10-31\n"))
        #expect(text.contains("# About Tony\n"))
        #expect(text.contains("## Work\n\nBuilds ZEUS\n"))
        #expect(text.contains("## What ZEUS should help with\n\nMornings and email\n"))
        #expect(!text.contains("## Notes"))
        #expect(text.contains("- 120 notes, mostly in 10_Projects, 20_Areas"))
        #expect(text.hasSuffix("Nothing left the Mac._\n"))
    }

    @Test func writerOnlyWritesInsideFromZeusAndNeverOverwrites() throws {
        let vault = try tempHome()
        defer { try? FileManager.default.removeItem(at: vault) }
        let date = Date(timeIntervalSince1970: 1_793_475_612)
        let utc = TimeZone(identifier: "UTC")!
        let first = ProfileNoteWriter.plannedURL(in: vault, created: date, timeZone: utc)
        #expect(first.path.hasSuffix("00_Inbox/from-zeus/zeus-profile-2026-10-31.md"))
        try ProfileNoteWriter.write("one", to: first, vault: vault)
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        let second = ProfileNoteWriter.plannedURL(in: vault, created: date, timeZone: utc)
        #expect(second.lastPathComponent == "zeus-profile-2026-10-31-2.md")
        #expect(throws: (any Error).self) { try ProfileNoteWriter.write("two", to: first, vault: vault) }
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(throws: ProfileNoteWriter.WriteError.outsideVault) {
            try ProfileNoteWriter.write("x", to: vault.appendingPathComponent("10_Projects/evil.md"), vault: vault)
        }
        #expect(throws: ProfileNoteWriter.WriteError.outsideVault) {
            try ProfileNoteWriter.write("x", to: ProfileNoteWriter.folder(in: vault).appendingPathComponent("../../escape.md"), vault: vault)
        }
        #expect(throws: ProfileNoteWriter.WriteError.notAVault) {
            try ProfileNoteWriter.write("x", to: first, vault: vault.appendingPathComponent("missing"))
        }
    }
}
