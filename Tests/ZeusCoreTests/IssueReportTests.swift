import Foundation
import Testing
@testable import ZeusCore

@Suite("Settings report")
struct IssueReportTests {
    private let home = "/Users/nobody"

    private func disposable() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-issue-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func record(in folder: URL) throws -> IssueReportRecord {
        let data = try Data(contentsOf: folder.appendingPathComponent("report.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IssueReportRecord.self, from: data)
    }

    @Test func theKindsAreABugOrAFeatureRequest() {
        #expect(IssueReportKind.allCases.map(\.title) == ["Bug", "Feature request"])
        #expect(IssueReportKind.bug.rawValue == "bug")
        #expect(IssueReportKind.feature.rawValue == "feature")
    }

    @Test func reduceMotionKeepsTheReportStill() {
        let motion = IssueReportMotion(reduced: true)
        #expect(motion.pressScale == 1)
        #expect(motion.pressDuration == nil)
        #expect(motion.selectionDuration == nil)
        #expect(motion.statusDuration == nil)
    }

    @Test func motionUsesTheSharedPressAndCrossfade() {
        let motion = IssueReportMotion(reduced: false)
        #expect(motion.pressScale == MotionTokens.pressScale)
        #expect(motion.pressScale == 0.98)
        #expect(motion.pressDuration == MotionTokens.pressDuration)
        #expect(motion.pressDuration == 0.12)
        #expect(motion.selectionDuration == MotionTokens.crossfadeDuration)
        #expect(motion.statusDuration == MotionTokens.crossfadeDuration)
    }

    @Test func anEmptyNoteIsRefusedAndNothingIsWritten() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        let delivery = IssueReportMailbox.submit(
            kind: .bug, note: "  \n", log: "synthetic", destination: nil, outbox: outbox, home: home)
        #expect(delivery == .refused(IssueReportMailbox.emptyNoteMessage))
        #expect(delivery.message == "Write a short note.")
        #expect(!FileManager.default.fileExists(atPath: outbox.path))
    }

    @Test func aLongNoteIsRefused() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let note = String(repeating: "a", count: IssueReportMailbox.noteLimit + 1)
        let delivery = IssueReportMailbox.submit(
            kind: .feature, note: note, log: "synthetic", destination: nil,
            outbox: root.appendingPathComponent("Outbox"), home: home)
        #expect(delivery == .refused(IssueReportMailbox.longNoteMessage))
    }

    @Test func aBugWithNoDestinationStaysInTheOutboxAndAttachesTheLog() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let logFile = root.appendingPathComponent("voice.log")
        let secret = "token=abc123def at \(home)/Library/Logs/Zeus/voice.log"
        try secret.write(to: logFile, atomically: true, encoding: .utf8)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try "vault-secret-phrase".write(to: vault.appendingPathComponent("Private.md"), atomically: true, encoding: .utf8)
        let attached = IssueReportLog.attach(recorder: "recorder-line", file: logFile, forbiddenRoots: [vault])
        #expect(attached.contains("recorder-line"))
        #expect(attached.contains("token=abc123def"))
        #expect(!attached.contains("vault-secret-phrase"))

        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        let delivery = IssueReportMailbox.submit(
            kind: .bug, note: "  The notch stayed open.  ", log: attached, destination: nil,
            outbox: outbox, now: created, id: id, home: home, forbiddenRoots: [vault])
        #expect(delivery.message == "Saved on this Mac.")
        let folder = try #require(delivery.folder)
        #expect(folder.path.hasPrefix(outbox.path))
        let saved = try record(in: folder)
        #expect(saved == IssueReportRecord(id: id, kind: .bug, note: "The notch stayed open.", created: created, log: "log.txt"))
        let log = try String(contentsOf: folder.appendingPathComponent("log.txt"), encoding: .utf8)
        #expect(log.contains("recorder-line"))
        #expect(log.contains("token=\(DiagnosticsRedactor.mask)"))
        #expect(log.contains("~/Library/Logs/Zeus/voice.log"))
        #expect(!log.contains(home))
        #expect(!log.contains("abc123def"))
        #expect(!log.contains("vault-secret-phrase"))
    }

    @Test func aFeatureRequestUsesTheSameOutboxWhenNothingIsConfigured() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let delivery = IssueReportMailbox.submit(
            kind: .feature, note: "A quieter completion chime", log: "", destination: nil,
            outbox: root.appendingPathComponent("Outbox"), home: home)
        #expect(delivery.message == IssueReportMailbox.savedMessage)
        let folder = try #require(delivery.folder)
        let saved = try record(in: folder)
        #expect(saved.kind == .feature)
        #expect(saved.note == "A quieter completion chime")
        let log = try String(contentsOf: folder.appendingPathComponent("log.txt"), encoding: .utf8)
        #expect(log == IssueReportMailbox.emptyLog + "\n")
    }

    @Test func aConfiguredLocalFolderReceivesTheReport() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Configured", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let delivery = IssueReportMailbox.submit(
            kind: .bug, note: "Export stopped halfway", log: "synthetic-log-line",
            destination: destination, outbox: outbox, home: home)
        #expect(delivery.message == "Sent.")
        let folder = try #require(delivery.folder)
        #expect(folder.path.hasPrefix(destination.path))
        #expect(try record(in: folder).note == "Export stopped halfway")
        #expect(try String(contentsOf: folder.appendingPathComponent("log.txt"), encoding: .utf8).contains("synthetic-log-line"))
        let leftover = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
        #expect(leftover.isEmpty)
    }

    @Test func mailAndWebValuesAreNotADestinationSoTheReportIsSaved() throws {
        #expect(IssueReportDestination.resolve(nil) == nil)
        #expect(IssueReportDestination.resolve("  ") == nil)
        #expect(IssueReportDestination.resolve("mailto:person@example.com") == nil)
        #expect(IssueReportDestination.resolve("person@example.com") == nil)
        #expect(IssueReportDestination.resolve("https://reports.example/inbox") == nil)
        #expect(IssueReportDestination.resolve("http://127.0.0.1/report") == nil)
        #expect(IssueReportDestination.resolve("relative/folder") == nil)

        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("destination")
        try "https://reports.example/inbox\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(IssueReportDestination.read(file: file) == nil)
        let delivery = IssueReportMailbox.submit(
            kind: .feature, note: "Show the report in Settings", log: "synthetic",
            destination: IssueReportDestination.read(file: file),
            outbox: root.appendingPathComponent("Outbox"), home: home)
        #expect(delivery.message == "Saved on this Mac.")
        #expect(delivery.folder != nil)
    }

    @Test func aDestinationFileNamesALocalFolder() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Drop", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = IssueReportLocations.destinationFile(in: IssueReportLocations.root(support: root))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try destination.path.write(to: file, atomically: true, encoding: .utf8)
        let resolved = IssueReportDestination.read(file: file)
        #expect(resolved?.path == destination.path)
        #expect(IssueReportLocations.outbox(in: IssueReportLocations.root(support: root)).path.hasPrefix(root.path))
    }

    @Test func aLogInsideAForbiddenRootIsNotOpened() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("PrivateVault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let secret = vault.appendingPathComponent("note.md")
        try "vault-secret-phrase".write(to: secret, atomically: true, encoding: .utf8)
        let destinationFile = vault.appendingPathComponent("destination")
        try "/tmp/should-not-be-read".write(to: destinationFile, atomically: true, encoding: .utf8)
        #expect(IssueReportLog.isInside(secret, roots: [vault]))
        #expect(IssueReportLog.attach(recorder: "kept", file: secret, forbiddenRoots: [vault]) == "kept")
        #expect(IssueReportDestination.read(file: destinationFile, forbiddenRoots: [vault]) == nil)
        let outbox = root.appendingPathComponent("Outbox", isDirectory: true)
        let delivery = IssueReportMailbox.submit(
            kind: .bug, note: "Outside the vault", log: "synthetic-log-line",
            destination: vault, outbox: outbox, home: home, forbiddenRoots: [vault])
        #expect(delivery.message == "Saved on this Mac.")
        let folder = try #require(delivery.folder)
        let savedLog = try String(contentsOf: folder.appendingPathComponent("log.txt"), encoding: .utf8)
        #expect(savedLog.contains("synthetic-log-line"))
        #expect(!savedLog.contains("vault-secret-phrase"))
        #expect(!folder.path.hasPrefix(vault.path))
    }

    @Test func aDestinationThatCannotBeWrittenFallsBackToTheOutbox() throws {
        let root = try disposable()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-folder")
        try "file".write(to: blocked, atomically: true, encoding: .utf8)
        let delivery = IssueReportMailbox.submit(
            kind: .bug, note: "Still here", log: "synthetic",
            destination: blocked, outbox: root.appendingPathComponent("Outbox"), home: home)
        #expect(delivery.message == "Saved on this Mac.")
        let folder = try #require(delivery.folder)
        #expect(folder.path.contains("Outbox"))
    }

    @Test func theReportSectionResolvesInSettings() {
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("report") == "report")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("Report") == "report")
        #expect(GlanceSettingsSnapshotMapping.resolveSectionID("  REPORT ") == "report")
    }
}
