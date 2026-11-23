import Foundation

/// What Zeus does when a part stops, or when the whole app crashes.
/// A part restarts once, then stays paused. The whole app restarts once.
/// A second crash before a stable quit is a loop: Zeus stays open instead of restarting again.
public enum RecoverablePart: String, Codable, CaseIterable, Sendable {
    case voice, dictation, notch, scribe, agents, settings

    public var title: String {
        switch self {
        case .voice: "Voice"
        case .dictation: "Dictation"
        case .notch: "Notch"
        case .scribe: "Scribe"
        case .agents: "Agents"
        case .settings: "Settings"
        }
    }
}

public enum RecoveryStep: Equatable, Sendable {
    case running
    case restartPart(RecoverablePart)
    case partFallback(RecoverablePart, String)
    case restartApp
    case stayUp(String)

    public var restartsApp: Bool {
        if case .restartApp = self { return true }
        return false
    }
}

/// Counts kept beside the outbox so a new process can see the restart that already happened.
public struct RecoveryLedger: Codable, Equatable, Sendable {
    public var appRestarts: Int
    public var stable: Bool
    public var partRestarts: [String: Int]
    public var partFallbacks: [String: String]
    public var fallback: String?
    /// The next launch should say the crash log was saved, then clear this.
    public var pendingSaved: Bool

    public init(appRestarts: Int = 0, stable: Bool = true, partRestarts: [String: Int] = [:],
                partFallbacks: [String: String] = [:], fallback: String? = nil, pendingSaved: Bool = false) {
        self.appRestarts = appRestarts
        self.stable = stable
        self.partRestarts = partRestarts
        self.partFallbacks = partFallbacks
        self.fallback = fallback
        self.pendingSaved = pendingSaved
    }
}

struct RecoverySession: Codable, Equatable, Sendable {
    var open: Bool
    var stages: [String]
    var openedAt: Date
}

/// A crash log an admin can read from the same outbox as a Settings report. Nothing is sent.
public struct CrashLogRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: String
    public var part: String
    public var reason: String
    public var created: Date
    public var log: String

    public init(id: UUID, kind: String, part: String, reason: String, created: Date, log: String) {
        self.id = id
        self.kind = kind
        self.part = part
        self.reason = reason
        self.created = created
        self.log = log
    }
}

public struct CrashRecoveryOutcome: Equatable, Sendable {
    public var step: RecoveryStep
    public var folder: URL?
    public var savedMessage: String?
    public var fallback: String?
}

public enum CrashRecovery {
    public static let savedMessage = IssueReportMailbox.savedMessage
    public static let loopMessage = "Zeus stayed open. Restarting again would repeat the crash, so this session continues."
    public static let logFileName = "log.txt"
    public static let emptyLog = "No local log entries."

    public static func partFallbackMessage(_ part: RecoverablePart) -> String {
        "\(part.title) is paused. The rest of Zeus keeps working."
    }

    public static func markerURL(in root: URL) -> URL { root.appendingPathComponent("session.json") }
    public static func ledgerURL(in root: URL) -> URL { root.appendingPathComponent("recovery.json") }

    /// Loads the ledger, applies `partStopped`, and writes it back.
    @discardableResult
    public static func partStopped(_ part: RecoverablePart, ledgerAt url: URL) -> RecoveryStep {
        var ledger = loadLedger(at: url)
        let step = partStopped(part, ledger: &ledger)
        save(ledger, at: url)
        return step
    }

    /// The first failure restarts the part. The next one leaves it paused so the rest of Zeus keeps working.
    public static func partStopped(_ part: RecoverablePart, ledger: inout RecoveryLedger) -> RecoveryStep {
        let count = ledger.partRestarts[part.rawValue, default: 0]
        if count >= 1 {
            let message = partFallbackMessage(part)
            ledger.partFallbacks[part.rawValue] = message
            return .partFallback(part, message)
        }
        ledger.partRestarts[part.rawValue] = 1
        ledger.partFallbacks[part.rawValue] = nil
        return .restartPart(part)
    }

    /// One full restart, then a refused loop while the previous run never became stable.
    public static func noteAppCrash(ledger: inout RecoveryLedger) -> RecoveryStep {
        if ledger.appRestarts >= 1 && !ledger.stable {
            ledger.fallback = loopMessage
            return .stayUp(loopMessage)
        }
        ledger.appRestarts = 1
        ledger.stable = false
        ledger.fallback = nil
        return .restartApp
    }

    /// Appends one redacted stage to the open session. A closed session is left alone.
    public static func note(_ stage: String, at markerAt: URL, home: String = NSHomeDirectory()) {
        guard var session = loadSession(at: markerAt), session.open else { return }
        let clean = DiagnosticsRedactor.redact(stage, home: home)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        session.stages.append(String(clean.prefix(240)))
        if session.stages.count > 40 { session.stages.removeFirst(session.stages.count - 40) }
        save(session, at: markerAt)
    }

    public static func openSession(at markerAt: URL, now: Date = Date()) {
        let session = RecoverySession(open: true, stages: ["launch"], openedAt: now)
        save(session, at: markerAt)
    }

    /// A clean quit marks the run stable so a later crash may restart once. A relaunch quit does not.
    public static func closeSession(at markerAt: URL, ledgerAt: URL, stable: Bool, now: Date = Date()) {
        var session = loadSession(at: markerAt) ?? RecoverySession(open: false, stages: [], openedAt: now)
        session.open = false
        save(session, at: markerAt)
        var ledger = loadLedger(at: ledgerAt)
        if stable {
            ledger.stable = true
            ledger.appRestarts = 0
            ledger.fallback = nil
            ledger.partRestarts = [:]
            ledger.partFallbacks = [:]
            ledger.pendingSaved = false
        }
        save(ledger, at: ledgerAt)
    }

    /// Reads an open session as a crash, saves a redacted log in the outbox, and decides the restart.
    /// Then opens a session for this launch. No address is read or written.
    public static func recover(
        markerAt: URL,
        ledgerAt: URL,
        outbox: URL,
        now: Date = Date(),
        id: UUID = UUID(),
        home: String = NSHomeDirectory(),
        forbiddenRoots: [URL] = []
    ) -> CrashRecoveryOutcome {
        let previous = loadSession(at: markerAt) ?? RecoverySession(open: false, stages: [], openedAt: now)
        var ledger = loadLedger(at: ledgerAt)
        var folder: URL?
        var step: RecoveryStep = .running
        if previous.open {
            let text = previous.stages.joined(separator: "\n")
            folder = capture(reason: text, part: "app", outbox: outbox, now: now, id: id, home: home, forbiddenRoots: forbiddenRoots)
            if folder != nil { ledger.pendingSaved = true }
            step = noteAppCrash(ledger: &ledger)
        }
        let showSaved = folder != nil || (step == .running && ledger.pendingSaved)
        if step != .restartApp { ledger.pendingSaved = false }
        save(RecoverySession(open: true, stages: ["launch"], openedAt: now), at: markerAt)
        save(ledger, at: ledgerAt)
        return CrashRecoveryOutcome(
            step: step,
            folder: folder,
            savedMessage: showSaved ? savedMessage : nil,
            fallback: ledger.fallback
        )
    }

    /// Writes the crash log only under `outbox`. A forbidden root is not opened and not written.
    @discardableResult
    public static func capture(
        reason: String,
        part: String,
        outbox: URL,
        now: Date = Date(),
        id: UUID = UUID(),
        home: String = NSHomeDirectory(),
        forbiddenRoots: [URL] = []
    ) -> URL? {
        if IssueReportLog.isInside(outbox, roots: forbiddenRoots) { return nil }
        let redacted = DiagnosticsRedactor.redact(reason, home: home).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (redacted.isEmpty ? emptyLog : String(redacted.prefix(8_000))) + "\n"
        let record = CrashLogRecord(id: id, kind: "crash", part: part, reason: firstLine(of: body), created: now, log: logFileName)
        let folder = outbox.appendingPathComponent(id.uuidString, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try Data(body.utf8).write(to: folder.appendingPathComponent(logFileName), options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: folder.appendingPathComponent("crash.json"), options: .atomic)
            return folder
        } catch {
            try? fileManager.removeItem(at: folder)
            return nil
        }
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text
        return String(line.prefix(240))
    }

    static func loadLedger(at url: URL) -> RecoveryLedger {
        guard let data = try? Data(contentsOf: url) else { return RecoveryLedger() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RecoveryLedger.self, from: data)) ?? RecoveryLedger()
    }

    private static func loadSession(at url: URL) -> RecoverySession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecoverySession.self, from: data)
    }

    private static func save(_ session: RecoverySession, at url: URL) {
        write(session, to: url)
    }

    private static func save(_ ledger: RecoveryLedger, at url: URL) {
        write(ledger, to: url)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
