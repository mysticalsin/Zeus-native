import CoreWLAN
import Darwin
import Foundation
import ZeusCore

/// The system side of a lid-closed session. Every change is journaled BEFORE it is made, so
/// ending, a crash or the `zeus insomnia-guard` backstop can always put it back.
/// Not main-actor: `InsomniaController` calls it on one serial queue only, which is why it is
/// `@unchecked Sendable`. Commands and signals are injected so tests never touch the Mac.
/// Ideas from Insomnia (MIT, Krish Garg and contributors); the code is Zeus's own.
final class LidSleepGuard: @unchecked Sendable {
    struct Options: Equatable, Sendable {
        var freezeBundleIDs: [String] = []
        var mute = true
        var lowPower = true
        var hotspotSSID = ""
        var nudge = false
        var nudgeMinutes = 10
    }

    struct ArmReport: Equatable, Sendable {
        var ok: Bool
        var message: String
    }

    struct LidReport: Equatable, Sendable {
        var frozen = 0
        var muted = false
        var lowPower = false
        var notes: [String] = []
    }

    struct NudgeReport: Equatable, Sendable {
        var tmuxMissing = false
        var nudged: [String] = []
        var checkedPanes = 0
    }

    let runner: any InsomniaCommandRunner
    let store: InsomniaJournalStore
    let signal: @Sendable (Int32, Int32) -> Bool
    let tmuxPath: () -> String?
    let zeusPID: Int32
    let zeusExecutable: String?
    private(set) var journal: InsomniaJournal?
    private var detector = TmuxStallDetector(stallAfter: 600)

    init(runner: any InsomniaCommandRunner = ProcessCommandRunner(),
         store: InsomniaJournalStore = InsomniaJournalStore(),
         signal: @escaping @Sendable (Int32, Int32) -> Bool = { kill($0, $1) == 0 },
         tmuxPath: @escaping () -> String? = { TmuxCommands.candidates.first(where: FileManager.default.isExecutableFile(atPath:)) },
         zeusPID: Int32 = getpid(),
         zeusExecutable: String? = Bundle.main.executablePath) {
        self.runner = runner
        self.store = store
        self.signal = signal
        self.tmuxPath = tmuxPath
        self.zeusPID = zeusPID
        self.zeusExecutable = zeusExecutable
    }

    var isArmed: Bool { journal != nil }
    var frozenCount: Int { journal?.frozenPIDs.count ?? 0 }

    private var restorer: InsomniaRestorer { InsomniaRestorer(runner: runner, store: store, signal: signal) }

    // MARK: Session

    /// A journal left by a crash or force quit: put it all back. Called at launch.
    func recoverLeftover() -> InsomniaRestorer.Report? {
        guard journal == nil, let leftover = store.load() else {
            if journal == nil, store.exists { return restorer.apply([.setSleepDisabled(false), .clearJournal]) }
            return nil
        }
        return restorer.apply(InsomniaRestorePlanner.plan(leftover))
    }

    /// Journal, then `sudo -n pmset -a disablesleep 1`. On failure nothing stays changed.
    func arm(plannedEnd: Date?, now: Date = Date()) -> ArmReport {
        if journal != nil {
            setPlannedEnd(plannedEnd)
            return ArmReport(ok: true, message: "Lid-closed mode on")
        }
        _ = recoverLeftover()
        let power = runner.run(InsomniaCommand.readPower.0, InsomniaCommand.readPower.1)
        let previous = power.ok && InsomniaParse.sleepDisabled(power.stdout)
        var fresh = InsomniaJournal(start: now, plannedEnd: plannedEnd, zeusPID: zeusPID, zeusExecutable: zeusExecutable)
        fresh.record(.disableSleep(previous: previous))
        do { try store.save(fresh) } catch {
            return ArmReport(ok: false, message: "Could not write the recovery journal: \(error.localizedDescription)")
        }
        journal = fresh
        let (tool, args) = InsomniaCommand.disableSleep(true)
        let result = runner.run(tool, args)
        guard result.ok else {
            restorer.apply([.clearJournal])
            journal = nil
            let needsRule = result.stderr.contains("password") || result.stderr.contains("sudo") || result.status == 1
            return ArmReport(ok: false, message: needsRule ? "Set up lid-closed mode first (the admin rule is missing)." : "pmset failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return ArmReport(ok: true, message: "Lid-closed mode on")
    }

    func setPlannedEnd(_ end: Date?) {
        guard var current = journal, current.plannedEnd != end else { return }
        current.plannedEnd = end
        journal = current
        try? store.save(current)
    }

    /// Ends the session: everything in the journal goes back, then the journal goes.
    @discardableResult
    func disarm() -> InsomniaRestorer.Report {
        let report = restorer.apply(InsomniaRestorePlanner.plan(journal ?? store.load()))
        journal = report.journalCleared ? nil : store.load()
        detector = TmuxStallDetector(stallAfter: detector.stallAfter)
        return report
    }

    // MARK: Lid

    /// Screen off, apps frozen, sound off, Low Power on battery.
    func lidClosed(options: Options, running: [InsomniaFreezePolicy.RunningProcess], onBattery: Bool) -> LidReport {
        var report = LidReport()
        guard journal != nil else { return report }
        _ = runner.run(InsomniaCommand.displaySleepNow.0, InsomniaCommand.displaySleepNow.1)

        for target in InsomniaFreezePolicy.targets(listed: options.freezeBundleIDs, running: running, zeusPID: zeusPID) {
            for pid in [target.pid] + children(of: target.pid) where pid != zeusPID {
                guard journalRecord(.frozen(pid: pid, bundleID: target.bundleID)) else { continue }
                if signal(pid, SIGSTOP) { report.frozen += 1 } else { forget(.frozen(pid: pid, bundleID: target.bundleID)) }
            }
        }

        if options.mute {
            let read = runner.run(InsomniaCommand.readVolume.0, InsomniaCommand.readVolume.1)
            if read.ok, let before = InsomniaParse.volume(read.stdout) {
                if !before.muted, journalRecord(.audio(volume: before.volume, muted: false)) {
                    report.muted = runner.run(InsomniaCommand.mute.0, InsomniaCommand.mute.1).ok
                }
            } else {
                report.notes.append("Could not read the volume, so sound stays as it is.")
            }
        }

        if options.lowPower, onBattery {
            let read = runner.run(InsomniaCommand.readPower.0, InsomniaCommand.readPower.1)
            if InsomniaParse.lowPowerMode(read.stdout) == false, journalRecord(.lowPowerMode(previous: false)) {
                let (tool, args) = InsomniaCommand.lowPowerMode(true)
                report.lowPower = runner.run(tool, args).ok
                if !report.lowPower { forget(.lowPowerMode(previous: false)); report.notes.append("Low Power Mode did not switch on.") }
            }
        }
        return report
    }

    /// Thaw, sound back, Low Power back. Sleep stays disabled until the session ends.
    func lidOpened() -> InsomniaRestorer.Report {
        guard var current = journal else { return .init() }
        let lidChanges = current.changes.filter { if case .disableSleep = $0 { false } else { true } }
        var partial = current
        partial.changes = lidChanges
        let report = restorer.apply(InsomniaRestorePlanner.plan(partial).filter { $0 != .clearJournal })
        for change in lidChanges { current.forget(change) }
        journal = current
        try? store.save(current)
        return report
    }

    // MARK: tmux

    /// One round: snapshot agent panes, nudge the ones stalled for `minutes`.
    func nudgeRound(minutes: Int, now: Date = Date()) -> NudgeReport {
        guard let tmux = tmuxPath() else { return NudgeReport(tmuxMissing: true) }
        detector.stallAfter = TimeInterval(max(1, minutes) * 60)
        let list = runner.run(tmux, TmuxCommands.listPanes)
        guard list.ok else { return NudgeReport() }
        var snapshots: [TmuxPaneSnapshot] = []
        for pane in TmuxCommands.parsePanes(list.stdout) where TmuxStallDetector.qualifies(pane.command) {
            let screen = runner.run(tmux, TmuxCommands.capture(pane.id))
            guard screen.ok else { continue }
            snapshots.append(TmuxPaneSnapshot(paneID: pane.id, command: pane.command,
                                              contentHash: TmuxCommands.hash(screen.stdout), time: now))
        }
        var report = NudgeReport(checkedPanes: snapshots.count)
        for pane in detector.observe(snapshots) {
            if runner.run(tmux, TmuxCommands.typeContinue(pane)).ok, runner.run(tmux, TmuxCommands.pressEnter(pane)).ok {
                report.nudged.append(pane)
            }
        }
        return report
    }

    // MARK: Hotspot

    /// Best effort: join the iPhone hotspot with CoreWLAN. Returns a line saying what happened.
    /// `password` comes from the Keychain (or nil to use the network macOS already knows).
    func joinHotspot(ssid: String, password: String?, locationAllowed: Bool) -> String {
        guard !ssid.isEmpty else { return "No hotspot set" }
        guard let interface = CWWiFiClient.shared().interface() else { return "No Wi-Fi interface" }
        guard interface.powerOn() else { return "Wi-Fi is off" }
        do {
            let networks = try interface.scanForNetworks(withSSID: ssid.data(using: .utf8))
            guard let network = networks.first else {
                return locationAllowed ? "\(ssid) not found nearby"
                    : "\(ssid) not found. Location permission is needed to scan Wi-Fi names (System Settings › Privacy › Location Services)."
            }
            try interface.associate(to: network, password: password)
            return "Joined \(ssid)"
        } catch {
            let text = (error as NSError).localizedDescription
            return password == nil ? "Could not join \(ssid): \(text). Save its password in Settings › Insomnia." : "Could not join \(ssid): \(text)"
        }
    }

    // MARK: Helpers

    /// Saves the change in the journal before it is made. False if the journal cannot be written.
    private func journalRecord(_ change: InsomniaJournal.Change) -> Bool {
        guard var current = journal else { return false }
        if current.changes.contains(change) { return false }
        current.record(change)
        do { try store.save(current) } catch { return false }
        journal = current
        return true
    }

    private func forget(_ change: InsomniaJournal.Change) {
        guard var current = journal else { return }
        current.forget(change)
        journal = current
        try? store.save(current)
    }

    /// Helper processes an app started (Electron renderers and the like).
    private func children(of pid: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 256)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return [] }
        return Array(buffer.prefix(Int(count))).filter { $0 > 1 }
    }
}
