import Foundation

/// One step that puts a journaled change back.
public enum InsomniaRestoreAction: Equatable, Sendable {
    /// SIGCONT, first, so a frozen app never waits on anything else.
    case resume(pid: Int32, bundleID: String)
    case restoreAudio(volume: Int, muted: Bool)
    case setLowPowerMode(Bool)
    case setSleepDisabled(Bool)
    case clearJournal
}

/// Given a journal, what to put back, and whether the backstop should act now.
public enum InsomniaRestorePlanner {
    /// How long past its planned end a session may run before the backstop steps in while Zeus is
    /// alive: Zeus ends its own sessions, so the backstop only acts when Zeus did not.
    public static let grace: TimeInterval = 120

    /// Why the backstop should restore, or nil to leave the session alone.
    public enum Reason: Equatable, Sendable {
        case zeusGone
        case pastEnd
    }

    public static func reason(_ journal: InsomniaJournal, now: Date, zeusAlive: Bool) -> Reason? {
        if !zeusAlive { return .zeusGone }
        if let end = journal.plannedEnd, now.timeIntervalSince(end) > grace { return .pastEnd }
        return nil
    }

    /// Every action that undoes the journal, in a safe order: thaw apps, sound, Low Power, sleep,
    /// then forget the journal. A change that did not alter anything (sleep was already disabled)
    /// is left alone.
    public static func plan(_ journal: InsomniaJournal?) -> [InsomniaRestoreAction] {
        guard let journal else { return [] }
        var actions: [InsomniaRestoreAction] = []
        for change in journal.changes {
            if case .frozen(let pid, let bundleID) = change { actions.append(.resume(pid: pid, bundleID: bundleID)) }
        }
        for change in journal.changes {
            if case .audio(let volume, let muted) = change { actions.append(.restoreAudio(volume: volume, muted: muted)) }
        }
        for change in journal.changes {
            if case .lowPowerMode(let previous) = change, !previous { actions.append(.setLowPowerMode(false)) }
        }
        for change in journal.changes {
            if case .disableSleep(let previous) = change, !previous { actions.append(.setSleepDisabled(false)) }
        }
        actions.append(.clearJournal)
        return actions
    }

    /// The backstop's whole decision: nothing without a journal or while the session is healthy.
    public static func backstopPlan(_ journal: InsomniaJournal?, now: Date, zeusAlive: Bool) -> [InsomniaRestoreAction] {
        guard let journal, reason(journal, now: now, zeusAlive: zeusAlive) != nil else { return [] }
        return plan(journal)
    }
}

/// Carries out restore actions. Shared by Zeus (session end, launch recovery) and the backstop.
public struct InsomniaRestorer: Sendable {
    public let runner: any InsomniaCommandRunner
    public let store: InsomniaJournalStore
    /// kill(2), injected so tests never signal a real process.
    public let signal: @Sendable (Int32, Int32) -> Bool

    public init(runner: any InsomniaCommandRunner, store: InsomniaJournalStore,
                signal: @escaping @Sendable (Int32, Int32) -> Bool = { kill($0, $1) == 0 }) {
        self.runner = runner
        self.store = store
        self.signal = signal
    }

    public struct Report: Equatable, Sendable {
        public var done: [InsomniaRestoreAction] = []
        public var failed: [String] = []
        /// False when sleep could not be turned back on; the journal then stays for the next try.
        public var journalCleared = false
        public var ok: Bool { failed.isEmpty }

        public init(done: [InsomniaRestoreAction] = [], failed: [String] = [], journalCleared: Bool = false) {
            self.done = done
            self.failed = failed
            self.journalCleared = journalCleared
        }
    }

    /// Runs each action; one failure never stops the rest. The journal is cleared only once sleep
    /// is back, so a Mac that cannot sleep is never forgotten.
    @discardableResult
    public func apply(_ actions: [InsomniaRestoreAction]) -> Report {
        var report = Report()
        var sleepRestored = true
        for action in actions {
            switch action {
            case .resume(let pid, let bundleID):
                // SIGCONT to a process that is not stopped, or is gone, does no harm.
                if signal(pid, SIGCONT) { report.done.append(action) } else { report.failed.append("resume \(bundleID) (\(pid)): gone") }
            case .restoreAudio(let volume, let muted):
                let (tool, args) = InsomniaCommand.restoreVolume(volume, muted: muted)
                record(runner.run(tool, args), action, "restore sound", &report)
            case .setLowPowerMode(let on):
                let (tool, args) = InsomniaCommand.lowPowerMode(on)
                record(runner.run(tool, args), action, "Low Power Mode \(on ? 1 : 0)", &report)
            case .setSleepDisabled(let on):
                let (tool, args) = InsomniaCommand.disableSleep(on)
                let result = runner.run(tool, args)
                if !result.ok { sleepRestored = false }
                record(result, action, "disablesleep \(on ? 1 : 0)", &report)
            case .clearJournal:
                guard sleepRestored else { continue }
                do {
                    try store.clear()
                    report.journalCleared = true
                    report.done.append(action)
                } catch {
                    report.failed.append("clear journal: \(error.localizedDescription)")
                }
            }
        }
        return report
    }

    private func record(_ result: InsomniaCommandResult, _ action: InsomniaRestoreAction, _ label: String, _ report: inout Report) {
        if result.ok {
            report.done.append(action)
        } else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            report.failed.append("\(label): exit \(result.status)\(detail.isEmpty ? "" : ", \(detail)")")
        }
    }
}

/// `zeus insomnia-guard`: what launchd runs every 60 s. Idempotent, and a no-op without a journal.
public enum InsomniaGuard {
    public enum Outcome: Equatable, Sendable {
        case noJournal
        case unreadableJournal
        case sessionHealthy
        case restored(InsomniaRestorePlanner.Reason, InsomniaRestorer.Report)
    }

    public static func run(restorer: InsomniaRestorer, now: Date = Date(),
                           isZeusAlive: (InsomniaJournal) -> Bool) -> Outcome {
        guard let journal = restorer.store.load() else {
            // A journal that exists but cannot be read still means sleep may be off: put it back.
            if restorer.store.exists {
                restorer.apply([.setSleepDisabled(false), .clearJournal])
                return .unreadableJournal
            }
            return .noJournal
        }
        let alive = isZeusAlive(journal)
        guard let reason = InsomniaRestorePlanner.reason(journal, now: now, zeusAlive: alive) else { return .sessionHealthy }
        return .restored(reason, restorer.apply(InsomniaRestorePlanner.plan(journal)))
    }

    /// One line for the backstop's log.
    public static func describe(_ outcome: Outcome) -> String {
        switch outcome {
        case .noJournal: "no session"
        case .unreadableJournal: "journal unreadable: turned sleep back on"
        case .sessionHealthy: "session running"
        case .restored(let reason, let report):
            "restored (\(reason == .zeusGone ? "Zeus is not running" : "session past its end")): "
                + "\(report.done.count) done" + (report.failed.isEmpty ? "" : ", failed: " + report.failed.joined(separator: "; "))
        }
    }
}

/// Whether the Zeus that wrote a journal still runs: the pid exists and, when the journal names
/// the binary, that pid runs that binary (a reused pid is not Zeus).
public enum InsomniaProcessProbe {
    public static func isAlive(_ journal: InsomniaJournal,
                               exists: (Int32) -> Bool = InsomniaProcessProbe.exists,
                               path: (Int32) -> String? = InsomniaProcessProbe.path) -> Bool {
        guard journal.zeusPID > 0, exists(journal.zeusPID) else { return false }
        guard let expected = journal.zeusExecutable, !expected.isEmpty else { return true }
        guard let actual = path(journal.zeusPID) else { return true }
        return URL(fileURLWithPath: actual).resolvingSymlinksInPath().path == URL(fileURLWithPath: expected).resolvingSymlinksInPath().path
    }

    public static func exists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
