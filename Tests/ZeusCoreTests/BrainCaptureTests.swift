import Foundation
import Testing
@testable import ZeusCore

@Suite("Brain capture")
struct BrainCaptureTests {
    /// Temp folders only; the real ~/Documents/brain is never touched.
    func tempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "x".write(to: url.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        return url
    }

    let date = Date(timeIntervalSince1970: 1_793_475_612)
    let utc = TimeZone(identifier: "UTC")!

    @Test func slugs() {
        #expect(BrainCapture.slug("Groceries for the Weekend!") == "groceries-for-the-weekend")
        #expect(BrainCapture.slug("Café résumé ideas, part 2") == "cafe-resume-ideas-part-2")
        #expect(BrainCapture.slug("one two three four five six seven") == "one-two-three-four-five-six")
        #expect(BrainCapture.slug("🙂 ✨") == "note")
        #expect(BrainCapture.slug("../../etc/passwd") == "etc-passwd")
    }

    @Test func noteFormat() {
        let text = BrainCapture.note(title: " Plan\nfor Monday ", body: "\n- call bank\n", source: "chat reply", created: date, timeZone: utc)
        #expect(text == "---\ntype: capture\nsource: zeus-chatreply\ncreated: 2026-10-31T19:40:12Z\ntags: [zeus, inbox]\n---\n\n# Plan for Monday\n\n- call bank\n")
        #expect(BrainCapture.note(title: "", body: "b", source: "", created: date, timeZone: utc).contains("# Note from ZEUS\n"))
    }

    @Test func writesOnlyNewNotesInsideFromZeus() throws {
        let vault = try tempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let first = BrainCapture.plannedURL(in: vault, title: "Weekly review", created: date, timeZone: utc)
        #expect(first.path.hasSuffix("00_Inbox/from-zeus/zeus-2026-10-31-weekly-review.md"))
        try ProfileNoteWriter.write("one", to: first, vault: vault)
        let second = BrainCapture.plannedURL(in: vault, title: "Weekly review", created: date, timeZone: utc)
        #expect(second.lastPathComponent == "zeus-2026-10-31-weekly-review-2.md")
        #expect(throws: (any Error).self) { try ProfileNoteWriter.write("two", to: first, vault: vault) }
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
    }

    @Test func vaultChoice() throws {
        let vault = try tempVault()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-home-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: vault)
            try? FileManager.default.removeItem(at: home)
        }
        #expect(BrainCapture.vault(saved: vault, home: home) == vault)
        #expect(BrainCapture.vault(saved: home.appendingPathComponent("gone"), home: home) == nil)
    }
}
