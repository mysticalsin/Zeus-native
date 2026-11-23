import AppKit
import ZeusCore

/// Launch and quit hooks for crash recovery. A crash log stays in the local outbox.
/// One full restart is started here; a loop returns to the running app instead.
@MainActor
enum CrashRecoveryLaunch {
    private static var relaunching = false

    /// True when this process is leaving so a fresh one can start. The caller should not start services.
    static func begin(policy: StartupPolicy) -> Bool {
        guard !policy.isQA, !TopBarStyle.isSnapshot else { return false }
        let root = IssueReportLocations.root(support: ZeusPaths.supportDirectory)
        let outcome = CrashRecovery.recover(
            markerAt: CrashRecovery.markerURL(in: root),
            ledgerAt: CrashRecovery.ledgerURL(in: root),
            outbox: IssueReportLocations.outbox(in: root)
        )
        CrashRecoveryNoticeModel.shared.apply(outcome)
        guard outcome.step.restartsApp, let executable = Bundle.main.executableURL else { return false }
        CrashRecovery.closeSession(
            at: CrashRecovery.markerURL(in: root),
            ledgerAt: CrashRecovery.ledgerURL(in: root),
            stable: false
        )
        let process = Process()
        process.executableURL = executable
        process.arguments = []
        do {
            try process.run()
        } catch {
            CrashRecovery.openSession(at: CrashRecovery.markerURL(in: root))
            return false
        }
        relaunching = true
        NSApp.terminate(nil)
        return true
    }

    /// A part that stops restarts once. The next stop pauses that part and leaves the rest of Zeus up.
    static func partStopped(_ part: RecoverablePart) -> RecoveryStep {
        guard !StartupPolicy.current.isQA, !TopBarStyle.isSnapshot else { return .running }
        let root = IssueReportLocations.root(support: ZeusPaths.supportDirectory)
        let step = CrashRecovery.partStopped(part, ledgerAt: CrashRecovery.ledgerURL(in: root))
        if case .partFallback(_, let message) = step {
            CrashRecoveryNoticeModel.shared.message = message
        }
        return step
    }

    static func end() {
        guard !StartupPolicy.current.isQA, !TopBarStyle.isSnapshot else { return }
        let root = IssueReportLocations.root(support: ZeusPaths.supportDirectory)
        CrashRecovery.closeSession(
            at: CrashRecovery.markerURL(in: root),
            ledgerAt: CrashRecovery.ledgerURL(in: root),
            stable: !relaunching
        )
    }
}
