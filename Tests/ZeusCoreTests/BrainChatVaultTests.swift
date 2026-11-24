import Foundation
import Testing
@testable import ZeusCore

@Suite("Brain chat vault")
struct BrainChatVaultTests {
    private let date = Date(timeIntervalSince1970: 1_793_475_612)
    private let utc = TimeZone(identifier: "UTC")!
    private let userID = "4F6A1C20-8B3E-4D11-9A70-2C5E8B1D0A44"
    private let replyID = "8C2E7B10-1A44-4F90-B331-0D6A9C2E5F18"

    private func inbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-chat-vault-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aFinishedChatLandsInTheInbox() throws {
        let folder = try inbox()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let lines = [
            BrainChatLine(record: userID, role: "user", text: "Bring the notes.", failed: false, created: date),
            BrainChatLine(record: replyID, role: "assistant", text: "They are on the desk.", failed: false, created: date),
        ]
        let result = BrainChatVault.send(title: "Monday", lines: lines, inbox: folder, timeZone: utc)
        #expect(result.written == [userID, replyID])
        let note = try String(contentsOf: folder.appendingPathComponent("zeus-chat-\(userID).md"), encoding: .utf8)
        #expect(note.contains("source: zeus-chat\nrecord: \(userID)\nrole: user\ncreated: 2026-10-31T19:40:12Z\n"))
        #expect(note.contains("# Monday\n\nBring the notes.\n"))
        #expect(!note.contains(folder.path))
        let reply = try String(contentsOf: folder.appendingPathComponent("zeus-chat-\(replyID).md"), encoding: .utf8)
        #expect(reply.contains("role: assistant\n"))
        #expect(reply.contains("They are on the desk."))
    }

    @Test func aSecondSendLeavesTheSameBytesAndAChangeRefreshesOnlyThatNote() throws {
        let folder = try inbox()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let first = BrainChatLine(record: userID, role: "user", text: "Bring the notes.", failed: false, created: date)
        let reply = BrainChatLine(record: replyID, role: "assistant", text: "They are on the desk.", failed: false, created: date)
        _ = BrainChatVault.send(title: "Monday", lines: [first, reply], inbox: folder, timeZone: utc)
        let again = BrainChatVault.send(title: "Monday", lines: [first, reply], inbox: folder, timeZone: utc)
        #expect(again.unchanged == [userID, replyID])
        #expect(again.written.isEmpty)
        let replyURL = folder.appendingPathComponent("zeus-chat-\(replyID).md")
        let before = try Data(contentsOf: replyURL)
        let edited = BrainChatLine(record: replyID, role: "assistant", text: "They are in the drawer.", failed: false, created: date)
        let refreshed = BrainChatVault.send(title: "Monday", lines: [edited], inbox: folder, timeZone: utc)
        #expect(refreshed.refreshed == [replyID])
        let after = try String(contentsOf: replyURL, encoding: .utf8)
        #expect(after.contains("They are in the drawer."))
        #expect(!after.contains("They are on the desk."))
        let userNote = try String(contentsOf: folder.appendingPathComponent("zeus-chat-\(userID).md"), encoding: .utf8)
        #expect(userNote.contains("Bring the notes."))
        #expect(try Data(contentsOf: replyURL) != before)
    }

    @Test func anEmptyFailedOrUnsafeLineIsNotSent() throws {
        let folder = try inbox()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let lines = [
            BrainChatLine(record: userID, role: "user", text: "   ", failed: false, created: date),
            BrainChatLine(record: replyID, role: "assistant", text: "The connection failed.", failed: true, created: date),
            BrainChatLine(record: "../vault/secret.md", role: "user", text: "nope", failed: false, created: date),
        ]
        let result = BrainChatVault.send(title: "Monday", lines: lines, inbox: folder, timeZone: utc)
        #expect(result.written.isEmpty)
        #expect(result.refreshed.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.isEmpty)
        #expect(!names.joined().contains("secret"))
        #expect(result.skipped.contains("../vault/secret.md"))
    }

    @Test func aForeignFileAndASymlinkAreLeftAlone() throws {
        let folder = try inbox()
        let root = folder.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: root) }
        let foreign = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let linked = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        let foreignURL = folder.appendingPathComponent("zeus-chat-\(foreign).md")
        try "keep-this-foreign-note".write(to: foreignURL, atomically: true, encoding: .utf8)
        let outside = root.appendingPathComponent("outside.md")
        try "outside-secret".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("zeus-chat-\(linked).md"),
                                                    withDestinationURL: outside)
        let result = BrainChatVault.send(title: "Monday", lines: [
            BrainChatLine(record: foreign, role: "user", text: "replace me", failed: false, created: date),
            BrainChatLine(record: linked, role: "assistant", text: "follow me", failed: false, created: date),
        ], inbox: folder, timeZone: utc)
        #expect(result.written.isEmpty)
        #expect(result.refreshed.isEmpty)
        #expect(try String(contentsOf: foreignURL, encoding: .utf8) == "keep-this-foreign-note")
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside-secret")
        #expect(result.skipped.contains(foreign))
        #expect(result.skipped.contains(linked))
    }
}
