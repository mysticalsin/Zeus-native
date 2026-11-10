import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Answers from a table and records each call; nothing is ever run.
private final class ScriptedRunner: InsomniaCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var answer: @Sendable (String) -> InsomniaCommandResult

    init(_ answer: @escaping @Sendable (String) -> InsomniaCommandResult) { self.answer = answer }

    func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult {
        let line = ([executable] + arguments).joined(separator: " ")
        lock.withLock { log.append(line) }
        return answer(line)
    }

    var lines: [String] { lock.withLock { log } }
}

private final class Signals: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    func send(_ pid: Int32, _ sig: Int32) -> Bool { lock.withLock { sent.append("\(sig == SIGSTOP ? "STOP" : sig == SIGCONT ? "CONT" : "\(sig)") \(pid)") }; return true }
    var list: [String] { lock.withLock { sent } }
}

@Suite struct InsomniaInstallerTests {
    private func temp() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-insomnia-app-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func statusReadsTheFileThenSudo() {
        let runner = ScriptedRunner { _ in .init(status: 0) }
        let absent = InsomniaInstaller(runner: runner, user: "tony", uid: 501, home: temp(), cliPath: "/z", logPath: "/l", fileExists: { _ in false })
        #expect(absent.status() == .notInstalled)
        #expect(runner.lines.isEmpty)
        let present = InsomniaInstaller(runner: runner, user: "tony", uid: 501, home: temp(), cliPath: "/z", logPath: "/l", fileExists: { $0 == InsomniaSudoers.path })
        #expect(present.status() == .installed)
        #expect(runner.lines == ["/usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1"])
        runner.answer = { _ in .init(status: 1, stderr: "sudo: a password is required") }
        #expect(present.status() == .needsRepair("sudo: a password is required"))
    }

    @Test func installRunsOneAdminPromptAndWritesThePlist() throws {
        let home = temp(), tmp = temp()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: tmp) }
        let runner = ScriptedRunner { _ in .init(status: 0) }
        let installer = InsomniaInstaller(runner: runner, user: "tony", uid: 501, home: home, temporaryDirectory: tmp,
                                          cliPath: "/Z/bin/zeus", logPath: tmp.appendingPathComponent("g.log").path, fileExists: { _ in true })
        #expect(installer.install() == .done("Set up. Close the lid and agents keep working."))
        let osascript = runner.lines.filter { $0.hasPrefix("/usr/bin/osascript") }
        #expect(osascript.count == 1)
        #expect(osascript[0].contains("visudo -cf"))
        #expect(osascript[0].contains("install -m 0440 -o root -g wheel"))
        #expect(osascript[0].contains("launchctl bootstrap gui/501"))
        #expect(osascript[0].hasSuffix("with administrator privileges"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: installer.plistURL), format: nil) as? [String: Any]
        #expect(plist?["ProgramArguments"] as? [String] == ["/Z/bin/zeus", "insomnia-guard"])
        // The temp rule file is gone afterwards.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: tmp.path))?.contains { $0.hasSuffix(".sudoers") } == false)
    }

    @Test func cancelLeavesNothingBehind() {
        let home = temp()
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = ScriptedRunner { line in
            line.hasPrefix("/usr/bin/osascript") ? .init(status: 1, stderr: "execution error: User canceled. (-128)") : .init(status: 0)
        }
        let installer = InsomniaInstaller(runner: runner, user: "tony", uid: 501, home: home, cliPath: "/z", logPath: home.appendingPathComponent("l").path, fileExists: { _ in false })
        #expect(installer.install() == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: installer.plistURL.path))
    }
}

@Suite struct LidSleepGuardTests {
    private func makeGuard(_ runner: ScriptedRunner, _ signals: Signals, store: InsomniaJournalStore) -> LidSleepGuard {
        LidSleepGuard(runner: runner, store: store, signal: { signals.send($0, $1) }, tmuxPath: { "/tmux" },
                      zeusPID: 4242, zeusExecutable: "/Z")
    }

    private static func answers(_ line: String) -> InsomniaCommandResult {
        if line == "/usr/bin/pmset -g" { return .init(status: 0, stdout: " sleep 1\n lowpowermode 0\n") }
        if line.hasSuffix("get volume settings") { return .init(status: 0, stdout: "output volume:44, input volume:50, alert volume:100, output muted:false") }
        return .init(status: 0)
    }

    @Test func journalsBeforeEveryChangeAndRestoresAll() {
        let files = InsomniaMemoryStore()
        let store = InsomniaJournalStore(files: files)
        let unjournaled = Signals()
        let runner = ScriptedRunner { line in
            // The journal must already hold the change when the command runs.
            let changes = store.load()?.changes ?? []
            if line.contains("disablesleep 1"), !changes.contains(.disableSleep(previous: false)) { _ = unjournaled.send(1, 0) }
            if line.contains("lowpowermode 1"), !changes.contains(.lowPowerMode(previous: false)) { _ = unjournaled.send(2, 0) }
            if line.hasSuffix("with output muted"), !changes.contains(.audio(volume: 44, muted: false)) { _ = unjournaled.send(3, 0) }
            return Self.answers(line)
        }
        let signals = Signals()
        let guardian = makeGuard(runner, signals, store: store)
        #expect(guardian.arm(plannedEnd: Date().addingTimeInterval(600)).ok)
        let running: [InsomniaFreezePolicy.RunningProcess] = [.init(pid: 777, bundleID: "com.hnc.Discord", name: "Discord"),
                                                              .init(pid: 4242, bundleID: "app.zeus.mac", name: "Zeus")]
        let options = LidSleepGuard.Options(freezeBundleIDs: ["com.hnc.Discord", "app.zeus.mac"], mute: true, lowPower: true)
        let closed = guardian.lidClosed(options: options, running: running, onBattery: true)
        #expect(closed.frozen >= 1 && closed.muted && closed.lowPower)
        #expect(signals.list.first == "STOP 777")
        #expect(!signals.list.contains("STOP 4242"))
        #expect(runner.lines.contains("/usr/bin/pmset displaysleepnow"))
        #expect(unjournaled.list.isEmpty)

        let opened = guardian.lidOpened()
        #expect(opened.ok)
        #expect(signals.list.contains("CONT 777"))
        #expect(store.load()?.changes == [.disableSleep(previous: false)]) // sleep stays off until the end

        let ended = guardian.disarm()
        #expect(ended.journalCleared)
        #expect(runner.lines.last == "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
        #expect(store.load() == nil)
        #expect(!guardian.isArmed)
    }

    @Test func armWithoutTheRuleChangesNothing() {
        let store = InsomniaJournalStore(files: InsomniaMemoryStore())
        let runner = ScriptedRunner { line in
            line.contains("disablesleep 1") ? .init(status: 1, stderr: "sudo: a password is required") : Self.answers(line)
        }
        let guardian = makeGuard(runner, Signals(), store: store)
        let report = guardian.arm(plannedEnd: nil)
        #expect(!report.ok)
        #expect(report.message.contains("Set up"))
        #expect(store.load() == nil)
        #expect(!guardian.isArmed)
    }

    @Test func nudgesStalledAgentPanesOnly() {
        let runner = ScriptedRunner { line in
            if line.contains("list-panes") { return .init(status: 0, stdout: "%1\tclaude\t0\t0\n%2\tzsh\t0\t0\n") }
            if line.contains("capture-pane") { return .init(status: 0, stdout: "waiting for input") }
            return .init(status: 0)
        }
        let guardian = makeGuard(runner, Signals(), store: InsomniaJournalStore(files: InsomniaMemoryStore()))
        let now = Date()
        #expect(guardian.nudgeRound(minutes: 4, now: now).nudged.isEmpty)
        #expect(guardian.nudgeRound(minutes: 4, now: now.addingTimeInterval(240)).nudged == ["%1"])
        #expect(guardian.nudgeRound(minutes: 4, now: now.addingTimeInterval(480)).nudged.isEmpty)
        #expect(runner.lines.contains("/tmux send-keys -t %1 -l continue"))
        #expect(runner.lines.contains("/tmux send-keys -t %1 Enter"))
        #expect(!runner.lines.contains { $0.contains("capture-pane -p -t %2") })
        let missing = LidSleepGuard(runner: runner, store: InsomniaJournalStore(files: InsomniaMemoryStore()), tmuxPath: { nil })
        #expect(missing.nudgeRound(minutes: 4).tmuxMissing)
    }
}
