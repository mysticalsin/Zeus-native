import Foundation

/// A bug or a feature request from Settings. No address and no server live here:
/// a configured local folder receives the report, and otherwise it stays in the outbox.
public enum IssueReportKind: String, Codable, Equatable, Sendable, CaseIterable {
    case bug
    case feature

    public var title: String {
        switch self {
        case .bug: "Bug"
        case .feature: "Feature request"
        }
    }
}

/// Press, selection and status timing for the report section.
/// Reduce Motion keeps every change immediate and does not scale the send button.
public struct IssueReportMotion: Equatable, Sendable {
    public var reduced: Bool

    public init(reduced: Bool) {
        self.reduced = reduced
    }

    /// 1 while Reduce Motion is on, so the pressed button does not shrink.
    public var pressScale: Double { reduced ? 1 : MotionTokens.pressScale }

    /// Nil under Reduce Motion: the press state is visible without a timed scale.
    public var pressDuration: Double? { reduced ? nil : MotionTokens.pressDuration }

    /// Nil under Reduce Motion: the selected kind changes immediately and the pill does not travel.
    public var selectionDuration: Double? { reduced ? nil : MotionTokens.crossfadeDuration }

    /// Nil under Reduce Motion: the saved or sent line is present immediately.
    public var statusDuration: Double? { reduced ? nil : MotionTokens.crossfadeDuration }
}

/// Where a report is written. The destination file is optional and local.
public enum IssueReportLocations {
    public static func root(support: URL) -> URL {
        support.appendingPathComponent("Reports", isDirectory: true)
    }

    public static func outbox(in root: URL) -> URL {
        root.appendingPathComponent("Outbox", isDirectory: true)
    }

    public static func destinationFile(in root: URL) -> URL {
        root.appendingPathComponent("destination")
    }
}

/// A local folder the owner configured. Mail, web addresses and blank text are not a destination.
public enum IssueReportDestination {
    public static func resolve(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("mailto:") || lower.hasPrefix("http:") || lower.hasPrefix("https:") { return nil }
        if text.contains("@") { return nil }
        if lower.hasPrefix("file:") {
            guard let url = URL(string: text), url.isFileURL else { return nil }
            return url
        }
        guard text.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: text, isDirectory: true)
    }

    /// Missing, unreadable, or inside a forbidden root means no destination. The file is not opened when it is forbidden.
    public static func read(file: URL, forbiddenRoots: [URL] = []) -> URL? {
        if IssueReportLog.isInside(file, roots: forbiddenRoots) { return nil }
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return resolve(raw)
    }
}

/// The local log attached to a report. A path inside a forbidden root is skipped and never opened.
public enum IssueReportLog {
    public static func isInside(_ url: URL, roots: [URL]) -> Bool {
        let target = url.pathComponents
        for root in roots {
            let base = root.pathComponents
            guard target.count >= base.count, Array(target.prefix(base.count)) == base else { continue }
            return true
        }
        return false
    }

    /// Recorder text, then a local log file that sits outside every forbidden root.
    public static func attach(recorder: String, file: URL?, forbiddenRoots: [URL] = []) -> String {
        var parts: [String] = []
        let recorderText = recorder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recorderText.isEmpty { parts.append(recorderText) }
        if let file, !isInside(file, roots: forbiddenRoots),
           let text = try? String(contentsOf: file, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        return parts.joined(separator: "\n")
    }
}

/// One saved report: the note and the name of the attached log.
public struct IssueReportRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: IssueReportKind
    public var note: String
    public var created: Date
    public var log: String

    public init(id: UUID, kind: IssueReportKind, note: String, created: Date, log: String) {
        self.id = id
        self.kind = kind
        self.note = note
        self.created = created
        self.log = log
    }
}

/// Saved in the outbox, written to a configured folder, or refused before anything is written.
public enum IssueReportDelivery: Equatable, Sendable {
    case saved(URL)
    case sent(URL)
    case refused(String)

    public var message: String {
        switch self {
        case .saved: IssueReportMailbox.savedMessage
        case .sent: IssueReportMailbox.sentMessage
        case .refused(let text): text
        }
    }

    public var folder: URL? {
        switch self {
        case .saved(let url), .sent(let url): url
        case .refused: nil
        }
    }
}

/// Writes a report and its log. An unconfigured destination stays in the outbox.
public enum IssueReportMailbox {
    public static let savedMessage = "Saved on this Mac."
    public static let sentMessage = "Sent."
    public static let emptyNoteMessage = "Write a short note."
    public static let longNoteMessage = "Keep the note short."
    public static let failedMessage = "Could not save the report."
    public static let noteLimit = 500
    public static let logFileName = "log.txt"
    public static let emptyLog = "No local log entries."

    public static func submit(
        kind: IssueReportKind,
        note: String,
        log: String,
        destination: URL?,
        outbox: URL,
        now: Date = Date(),
        id: UUID = UUID(),
        home: String = NSHomeDirectory(),
        forbiddenRoots: [URL] = []
    ) -> IssueReportDelivery {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .refused(emptyNoteMessage) }
        if trimmed.count > noteLimit { return .refused(longNoteMessage) }
        let cleanNote = DiagnosticsRedactor.redact(trimmed, home: home)
        let redactedLog = DiagnosticsRedactor.redact(log, home: home).trimmingCharacters(in: .whitespacesAndNewlines)
        let logBody = (redactedLog.isEmpty ? emptyLog : redactedLog) + "\n"
        let record = IssueReportRecord(id: id, kind: kind, note: cleanNote, created: now, log: logFileName)

        let configured = destination.flatMap { candidate -> URL? in
            IssueReportLog.isInside(candidate, roots: forbiddenRoots) ? nil : candidate
        }
        if let configured, let folder = write(record, log: logBody, directory: configured) {
            return .sent(folder)
        }
        if IssueReportLog.isInside(outbox, roots: forbiddenRoots) { return .refused(failedMessage) }
        if let folder = write(record, log: logBody, directory: outbox) {
            return .saved(folder)
        }
        return .refused(failedMessage)
    }

    private static func write(_ record: IssueReportRecord, log: String, directory: URL) -> URL? {
        let folder = directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try Data(log.utf8).write(to: folder.appendingPathComponent(logFileName), options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: folder.appendingPathComponent("report.json"), options: .atomic)
            return folder
        } catch {
            try? fileManager.removeItem(at: folder)
            return nil
        }
    }
}
