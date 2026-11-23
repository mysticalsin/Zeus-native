import Foundation
import Testing
@testable import ZeusCore

@Suite("Crash recovery")
struct CrashRecoveryTests {
    private let home = "/Users/nobody"

    private func disposable() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-crash-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func crash(in folder: URL) throws -> CrashLogRecord {
        let data = try Data(contentsOf: folder.appendingPathComponent("crash.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CrashLogRecord.self, from: data)
    }

    @Test func aPartRestartsOnceThenUsesAFallback() {
        var ledger = RecoveryLedger()
        #expect(CrashRecovery.partStopped(.voice, ledger: &ledger) == .restartPart(.voice))
        let paused = CrashRecovery.partFallbackMessage(.voice)
        #expect(CrashRecovery.partStopped(.voice, ledger: &ledger) == .partFallback(.voice, paused))
        #expect(ledger.partRestarts["voice"] == 1)
        #expect(CrashRecovery.partStopped(.notch, ledger: &ledger) == .restartPart(.notch))
        #expect(paused == "Voice is paused. The rest of Zeus keeps working.")
    }

    @Test func theFirstCrashAllowsOneRestartAndSavesARedactedLog() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("PrivateVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "vault-secret-phrase".write(to: vault.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        let destination = root.appendingPathComponent("Configured", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "https://reports.example/inbox".write(to: destination.appendingPathComponent("destination"), atomically: true, encoding: .utf8)

        let marker = CrashRecovery.markerURL(in: root)
        let ledger = CrashRecovery.ledgerURL(in: root)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        let opened = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home, forbiddenRoots: [vault])
        #expect(opened.step == .running)
        #expect(opened.folder == nil)

        CrashRecovery.note("token=abc123def at \(home)/Library/Logs/crash.log", at: marker, home: home)
        let id = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let crash = CrashRecovery.recover(
            markerAt: marker, ledgerAt: ledger, outbox: outbox, now: created, id: id, home: home, forbiddenRoots: [vault])
        #expect(crash.step == .restartApp)
        #expect(crash.step.restartsApp)
        #expect(crash.savedMessage == "Saved on this Mac.")
        let folder = try #require(crash.folder)
        #expect(folder.path.hasPrefix(outbox.path))
        let saved = try self.crash(in: folder)
        #expect(saved.kind == "crash")
        #expect(saved.part == "app")
        #expect(saved.id == id)
        #expect(saved.created == created)
        let log = try String(contentsOf: folder.appendingPathComponent("log.txt"), encoding: .utf8)
        #expect(log.contains("token=\(DiagnosticsRedactor.mask)"))
        #expect(log.contains("~/Library/Logs/crash.log"))
        #expect(!log.contains("abc123def"))
        #expect(!log.contains(home))
        #expect(!log.contains("vault-secret-phrase"))
        #expect(!log.contains("http"))
        #expect(!log.contains("mailto"))
        let stored = try String(contentsOf: ledger, encoding: .utf8)
        let ledgerValue = try JSONDecoder().decode(RecoveryLedger.self, from: Data(stored.utf8))
        #expect(ledgerValue.appRestarts == 1)
        #expect(!ledgerValue.stable)
        let sent = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        #expect(sent.map(\.lastPathComponent) == ["destination"])
    }

    @Test func aSecondCrashBeforeTheAppIsStableRefusesTheLoop() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = CrashRecovery.markerURL(in: root)
        let ledger = CrashRecovery.ledgerURL(in: root)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        _ = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        let first = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        #expect(first.step == .restartApp)
        let again = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        #expect(again.step == .stayUp(CrashRecovery.loopMessage))
        #expect(!again.step.restartsApp)
        #expect(again.fallback == CrashRecovery.loopMessage)
        #expect(again.savedMessage == "Saved on this Mac.")
        let stored = CrashRecovery.loadLedger(at: ledger)
        #expect(stored.appRestarts == 1)
        #expect(stored.fallback == CrashRecovery.loopMessage)
        let logs = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
        #expect(logs.count == 2)
    }

    @Test func aCleanQuitLetsALaterCrashRestartOnce() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = CrashRecovery.markerURL(in: root)
        let ledger = CrashRecovery.ledgerURL(in: root)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        _ = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        _ = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        CrashRecovery.closeSession(at: marker, ledgerAt: ledger, stable: true)
        _ = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        let later = CrashRecovery.recover(markerAt: marker, ledgerAt: ledger, outbox: outbox, home: home)
        #expect(later.step == .restartApp)
    }

    @Test func aForbiddenOutboxIsNotWritten() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("PrivateVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "vault-secret-phrase".write(to: vault.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        let folder = CrashRecovery.capture(
            reason: "synthetic crash", part: "app", outbox: vault.appendingPathComponent("Outbox"),
            home: home, forbiddenRoots: [vault])
        #expect(folder == nil)
        let after = try FileManager.default.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        #expect(after == before)
        let note = try String(contentsOf: vault.appendingPathComponent("note.md"), encoding: .utf8)
        #expect(note == "vault-secret-phrase")
    }
}
