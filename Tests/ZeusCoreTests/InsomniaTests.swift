import Foundation
import Testing
@testable import ZeusCore

/// Records every command and answers from a table; never runs anything.
private final class FakeRunner: InsomniaCommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String]] = []
    let answer: @Sendable ([String]) -> InsomniaCommandResult

    init(answer: @escaping @Sendable ([String]) -> InsomniaCommandResult = { _ in .init(status: 0) }) {
        self.answer = answer
    }

    func run(_ executable: String, _ arguments: [String]) -> InsomniaCommandResult {
        let line = [executable] + arguments
        lock.withLock { calls.append(line) }
        return answer(line)
    }

    var lines: [String] { lock.withLock { calls.map { $0.joined(separator: " ") } } }
}

private final class SignalLog: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(Int32, Int32)] = []
    func record(_ pid: Int32, _ sig: Int32) -> Bool { lock.withLock { sent.append((pid, sig)) }; return true }
    var pids: [Int32] { lock.withLock { sent.map(\.0) } }
    var signals: [Int32] { lock.withLock { sent.map(\.1) } }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func journal(end: Date? = start.addingTimeInterval(3600), changes: [InsomniaJournal.Change] = []) -> InsomniaJournal {
    InsomniaJournal(sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, start: start, plannedEnd: end,
                    zeusPID: 4242, zeusExecutable: "/Applications/Zeus.app/Contents/MacOS/Zeus", changes: changes)
}

@Suite struct InsomniaJournalTests {
    @Test func roundTripsThroughTheStore() throws {
        let files = InsomniaMemoryStore()
        let store = InsomniaJournalStore(files: files)
        #expect(store.load() == nil)
        #expect(!store.exists)
        let saved = journal(changes: [.disableSleep(previous: false), .lowPowerMode(previous: false),
                                      .frozen(pid: 501, bundleID: "com.tinyspeck.slackmacgap"), .audio(volume: 37, muted: false)])
        try store.save(saved)
        #expect(store.load() == saved)
        #expect(files.writes == 1)
        try store.clear()
        #expect(store.load() == nil)
    }

    @Test func indefiniteSessionsKeepANilEnd() throws {
        let store = InsomniaJournalStore(files: InsomniaMemoryStore())
        try store.save(journal(end: nil))
        #expect(store.load()?.plannedEnd == nil)
    }

    @Test func diskStoreIsOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-insomnia-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(InsomniaJournal.fileName)
        let store = InsomniaJournalStore(files: InsomniaDiskStore(url: url))
        try store.save(journal())
        #expect(store.load() == journal())
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try store.clear()
        try store.clear() // twice is fine
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theFirstBeforeValueWins() {
        var entry = journal()
        entry.record(.audio(volume: 40, muted: false))
        entry.record(.audio(volume: 0, muted: true))
        entry.record(.frozen(pid: 10, bundleID: "a"))
        entry.record(.frozen(pid: 11, bundleID: "a"))
        #expect(entry.changes == [.audio(volume: 40, muted: false), .frozen(pid: 10, bundleID: "a"), .frozen(pid: 11, bundleID: "a")])
        #expect(entry.frozenPIDs == [10, 11])
        entry.forget(.frozen(pid: 10, bundleID: "a"))
        #expect(entry.frozenPIDs == [11])
    }

    @Test func unreadableJournalIsNotTrusted() {
        let store = InsomniaJournalStore(files: InsomniaMemoryStore(Data("not json".utf8)))
        #expect(store.load() == nil)
        #expect(store.exists)
    }
}

@Suite struct InsomniaRestorePlannerTests {
    @Test func noJournalNoActions() {
        #expect(InsomniaRestorePlanner.plan(nil).isEmpty)
        #expect(InsomniaRestorePlanner.backstopPlan(nil, now: start, zeusAlive: false).isEmpty)
    }

    @Test func emptyJournalOnlyClears() {
        #expect(InsomniaRestorePlanner.plan(journal()) == [.clearJournal])
    }

    @Test func everyChangeInASafeOrder() {
        let entry = journal(changes: [.disableSleep(previous: false), .audio(volume: 50, muted: false),
                                      .frozen(pid: 7, bundleID: "com.hnc.Discord"), .lowPowerMode(previous: false),
                                      .frozen(pid: 8, bundleID: "com.hnc.Discord")])
        #expect(InsomniaRestorePlanner.plan(entry) == [
            .resume(pid: 7, bundleID: "com.hnc.Discord"), .resume(pid: 8, bundleID: "com.hnc.Discord"),
            .restoreAudio(volume: 50, muted: false), .setLowPowerMode(false), .setSleepDisabled(false), .clearJournal,
        ])
    }

    @Test func settingsThatWereAlreadyOnStayOn() {
        let entry = journal(changes: [.disableSleep(previous: true), .lowPowerMode(previous: true)])
        #expect(InsomniaRestorePlanner.plan(entry) == [.clearJournal])
    }

    @Test func backstopLeavesAHealthySessionAlone() {
        let entry = journal(changes: [.disableSleep(previous: false)])
        #expect(InsomniaRestorePlanner.reason(entry, now: start.addingTimeInterval(60), zeusAlive: true) == nil)
        #expect(InsomniaRestorePlanner.backstopPlan(entry, now: start.addingTimeInterval(60), zeusAlive: true).isEmpty)
        // Within the grace after the end, Zeus is expected to end it itself.
        #expect(InsomniaRestorePlanner.reason(entry, now: start.addingTimeInterval(3600 + 60), zeusAlive: true) == nil)
        // Indefinitely, with Zeus alive: never.
        #expect(InsomniaRestorePlanner.reason(journal(end: nil), now: start.addingTimeInterval(86_400 * 7), zeusAlive: true) == nil)
    }

    @Test func backstopActsPastTheEndOrWhenZeusIsGone() {
        let entry = journal(changes: [.disableSleep(previous: false)])
        #expect(InsomniaRestorePlanner.reason(entry, now: start.addingTimeInterval(3600 + 121), zeusAlive: true) == .pastEnd)
        #expect(InsomniaRestorePlanner.reason(entry, now: start, zeusAlive: false) == .zeusGone)
        #expect(InsomniaRestorePlanner.reason(journal(end: nil), now: start, zeusAlive: false) == .zeusGone)
        #expect(InsomniaRestorePlanner.backstopPlan(entry, now: start, zeusAlive: false) == [.setSleepDisabled(false), .clearJournal])
    }
}

@Suite struct InsomniaGuardTests {
    private func setup(_ entry: InsomniaJournal?, runner: FakeRunner = FakeRunner()) throws -> (InsomniaRestorer, InsomniaJournalStore, SignalLog) {
        let store = InsomniaJournalStore(files: InsomniaMemoryStore())
        if let entry { try store.save(entry) }
        let log = SignalLog()
        return (InsomniaRestorer(runner: runner, store: store, signal: { log.record($0, $1) }), store, log)
    }

    @Test func safeWithNoJournal() throws {
        let runner = FakeRunner()
        let (restorer, _, log) = try setup(nil, runner: runner)
        #expect(InsomniaGuard.run(restorer: restorer, now: start) { _ in false } == .noJournal)
        #expect(runner.lines.isEmpty)
        #expect(log.pids.isEmpty)
    }

    @Test func healthySessionIsLeftAlone() throws {
        let runner = FakeRunner()
        let (restorer, store, _) = try setup(journal(changes: [.disableSleep(previous: false)]), runner: runner)
        #expect(InsomniaGuard.run(restorer: restorer, now: start.addingTimeInterval(10)) { _ in true } == .sessionHealthy)
        #expect(runner.lines.isEmpty)
        #expect(store.load() != nil)
    }

    @Test func restoresEverythingWhenZeusIsGoneThenIsIdempotent() throws {
        let runner = FakeRunner()
        let entry = journal(changes: [.disableSleep(previous: false), .lowPowerMode(previous: false),
                                      .frozen(pid: 900, bundleID: "com.tinyspeck.slackmacgap"), .audio(volume: 25, muted: false)])
        let (restorer, store, log) = try setup(entry, runner: runner)
        let outcome = InsomniaGuard.run(restorer: restorer, now: start) { _ in false }
        guard case .restored(.zeusGone, let report) = outcome else { Issue.record("expected a restore, got \(outcome)"); return }
        #expect(report.ok && report.journalCleared)
        #expect(log.pids == [900] && log.signals == [SIGCONT])
        #expect(runner.lines == [
            "/usr/bin/osascript -e set volume output volume 25 -e set volume without output muted",
            "/usr/bin/sudo -n /usr/bin/pmset -a lowpowermode 0",
            "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0",
        ])
        #expect(store.load() == nil)
        // Second run: nothing left to do.
        #expect(InsomniaGuard.run(restorer: restorer, now: start) { _ in false } == .noJournal)
        #expect(runner.lines.count == 3)
    }

    @Test func keepsTheJournalWhenSleepCannotBeRestored() throws {
        let runner = FakeRunner { line in
            line.contains("disablesleep") ? .init(status: 1, stderr: "sudo: a password is required") : .init(status: 0)
        }
        let (restorer, store, _) = try setup(journal(changes: [.disableSleep(previous: false)]), runner: runner)
        guard case .restored(.pastEnd, let report) = InsomniaGuard.run(restorer: restorer, now: start.addingTimeInterval(7200), isZeusAlive: { _ in true }) else {
            Issue.record("expected a restore"); return
        }
        #expect(!report.journalCleared)
        #expect(report.failed.first?.contains("password") == true)
        #expect(store.load() != nil)
    }

    @Test func unreadableJournalStillTurnsSleepBackOn() throws {
        let runner = FakeRunner()
        let files = InsomniaMemoryStore(Data("{".utf8))
        let restorer = InsomniaRestorer(runner: runner, store: InsomniaJournalStore(files: files), signal: { _, _ in true })
        #expect(InsomniaGuard.run(restorer: restorer, now: start) { _ in true } == .unreadableJournal)
        #expect(runner.lines == ["/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"])
        #expect((try? files.read()) ?? nil == nil)
    }

    @Test func aReusedPidIsNotZeus() {
        let entry = journal()
        #expect(InsomniaProcessProbe.isAlive(entry, exists: { _ in true }, path: { _ in "/Applications/Zeus.app/Contents/MacOS/Zeus" }))
        #expect(!InsomniaProcessProbe.isAlive(entry, exists: { _ in true }, path: { _ in "/usr/bin/vim" }))
        #expect(!InsomniaProcessProbe.isAlive(entry, exists: { _ in false }, path: { _ in nil }))
    }
}

@Suite struct InsomniaSudoersTests {
    @Test func exactUserScopedRule() throws {
        let text = try InsomniaSudoers.rule(user: "tony")
        #expect(text == """
        # Zeus lid-closed mode (Insomnia). Lets tony run these four pmset commands without a password.
        # Remove it in Zeus > Settings > Insomnia, or: sudo rm /etc/sudoers.d/zeus-insomnia
        tony ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -a lowpowermode 0

        """)
        #expect(InsomniaSudoers.path == "/etc/sudoers.d/zeus-insomnia")
    }

    @Test func noWildcardsAndOnlyFourCommands() throws {
        let text = try InsomniaSudoers.rule(user: "tony")
        let ruleLines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(ruleLines.count == 1)
        for forbidden in ["*", "?", "[", "%", "ALL:", "ALL, ", "NOPASSWD: ALL", "!"] { #expect(!ruleLines[0].contains(forbidden)) }
        #expect(ruleLines[0].hasPrefix("tony "))
        #expect(InsomniaSudoers.commands.count == 4)
        #expect(ruleLines[0].components(separatedBy: "/usr/bin/pmset").count - 1 == 4)
        #expect(text.hasSuffix("\n"))
    }

    @Test func refusesNamesThatAreNotPlainUsers() {
        for bad in ["", "root", "ALL", "%admin", "tony ALL", "to*ny", "-tony", "tony\nALL", "a,b"] {
            #expect(throws: InsomniaSudoers.RuleError.self) { try InsomniaSudoers.rule(user: bad) }
        }
        #expect((try? InsomniaSudoers.rule(user: "tony.stark_2")) != nil)
    }

    @Test func installScriptValidatesThenInstallsRootWheel0440() {
        let script = InsomniaAdminScript.install(ruleFile: "/tmp/x y.sudoers", plist: "/Users/tony/Library/LaunchAgents/com.zeus.insomnia.backstop.plist", uid: 501)
        #expect(script == "/usr/sbin/visudo -cf '/tmp/x y.sudoers' && /usr/bin/install -m 0440 -o root -g wheel '/tmp/x y.sudoers' '/etc/sudoers.d/zeus-insomnia' && /usr/sbin/visudo -cf '/etc/sudoers.d/zeus-insomnia' && (/bin/launchctl bootout gui/501/com.zeus.insomnia.backstop 2>/dev/null || true) && /bin/launchctl bootstrap gui/501 '/Users/tony/Library/LaunchAgents/com.zeus.insomnia.backstop.plist'")
        let uninstall = InsomniaAdminScript.uninstall(plist: "/p.plist", uid: 501)
        #expect(uninstall == "/bin/launchctl bootout gui/501/com.zeus.insomnia.backstop 2>/dev/null; /bin/rm -f '/p.plist'; /bin/rm -f '/etc/sudoers.d/zeus-insomnia'")
    }

    @Test func quotingIsSafe() {
        #expect(InsomniaAdminScript.shellQuote("it's") == "'it'\\''s'")
        #expect(InsomniaAdminScript.appleScriptEscape(#"a "b" \c"#) == #"a \"b\" \\c"#)
        let args = InsomniaAdminScript.osascriptArguments("echo 'x'", prompt: "Zeus")
        #expect(args == ["-e", #"do shell script "echo 'x'" with prompt "Zeus" with administrator privileges"#])
    }

    @Test func backstopPlistRunsTheGuardEveryMinute() throws {
        let data = try InsomniaBackstop.plist(cliPath: "/Users/tony/Library/Application Support/Zeus/bin/zeus", logPath: "/tmp/log")
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["Label"] as? String == "com.zeus.insomnia.backstop")
        #expect(plist?["ProgramArguments"] as? [String] == ["/Users/tony/Library/Application Support/Zeus/bin/zeus", "insomnia-guard"])
        #expect(plist?["StartInterval"] as? Int == 60)
        #expect(InsomniaBackstop.plistURL(home: URL(fileURLWithPath: "/Users/tony")).path == "/Users/tony/Library/LaunchAgents/com.zeus.insomnia.backstop.plist")
    }

    @Test func commandLinesAreExact() {
        #expect(InsomniaCommand.disableSleep(true).1 == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(InsomniaCommand.lowPowerMode(false).1 == ["-n", "/usr/bin/pmset", "-a", "lowpowermode", "0"])
        #expect(InsomniaCommand.sudoAllows().1 == ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(InsomniaCommand.displaySleepNow.1 == ["displaysleepnow"])
    }
}

@Suite struct InsomniaParseTests {
    @Test func pmsetOutput() {
        let on = " sleep                1\n SleepDisabled        1\n lowpowermode         0\n"
        #expect(InsomniaParse.sleepDisabled(on))
        #expect(!InsomniaParse.sleepDisabled(" sleep 1\n lowpowermode 1\n"))
        #expect(InsomniaParse.lowPowerMode(on) == false)
        #expect(InsomniaParse.lowPowerMode(" lowpowermode 1") == true)
        #expect(InsomniaParse.lowPowerMode(" powermode 1") == true)
        #expect(InsomniaParse.lowPowerMode(" powermode 2") == nil)
        #expect(InsomniaParse.lowPowerMode(" sleep 1") == nil)
    }

    @Test func volumeSettings() {
        let parsed = InsomniaParse.volume("output volume:50, input volume:75, alert volume:100, output muted:false\n")
        #expect(parsed?.volume == 50 && parsed?.muted == false)
        #expect(InsomniaParse.volume("output volume:missing value, output muted:missing value") == nil)
    }
}

@Suite struct TmuxStallDetectorTests {
    private func snap(_ id: String, _ command: String = "claude", hash: UInt64, at minutes: Double) -> TmuxPaneSnapshot {
        TmuxPaneSnapshot(paneID: id, command: command, contentHash: hash, time: start.addingTimeInterval(minutes * 60))
    }

    @Test func nudgesOncePerStall() {
        var detector = TmuxStallDetector(stallAfter: 10 * 60)
        #expect(detector.observe([snap("%1", hash: 1, at: 0)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 1, at: 6)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 1, at: 10)]) == ["%1"])
        // Still stalled: no second nudge.
        #expect(detector.observe([snap("%1", hash: 1, at: 12)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 1, at: 40)]).isEmpty)
        // The screen moved, then stalled again: one more.
        #expect(detector.observe([snap("%1", hash: 2, at: 42)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 2, at: 51)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 2, at: 52)]) == ["%1"])
    }

    @Test func aWorkingPaneIsNeverNudged() {
        var detector = TmuxStallDetector(stallAfter: 4 * 60)
        for minute in stride(from: 0.0, through: 30, by: 2) {
            #expect(detector.observe([snap("%2", "codex", hash: UInt64(minute), at: minute)]).isEmpty)
        }
    }

    @Test func onlyAgentsQualifyNeverAShell() {
        var detector = TmuxStallDetector(stallAfter: 60)
        let panes = ["zsh", "bash", "fish", "vim", "claude", "codex", "gemini", "cursor-agent", "node", "/usr/local/bin/node"]
        let first = panes.enumerated().map { snap("%\($0.offset)", $0.element, hash: 9, at: 0) }
        let later = panes.enumerated().map { snap("%\($0.offset)", $0.element, hash: 9, at: 5) }
        #expect(detector.observe(first).isEmpty)
        #expect(detector.observe(later) == ["%4", "%5", "%6", "%7", "%8", "%9"])
        #expect(!TmuxStallDetector.qualifies("zsh") && !TmuxStallDetector.qualifies("-zsh") && !TmuxStallDetector.qualifies("python"))
    }

    @Test func aPaneThatBecameAShellIsForgotten() {
        var detector = TmuxStallDetector(stallAfter: 60)
        _ = detector.observe([snap("%1", hash: 1, at: 0)])
        _ = detector.observe([snap("%1", "zsh", hash: 1, at: 1)])
        // Back to an agent: the stall clock starts again.
        #expect(detector.observe([snap("%1", hash: 1, at: 1.5)]).isEmpty)
        #expect(detector.observe([snap("%1", hash: 1, at: 2.5)]) == ["%1"])
    }

    @Test func listPanesParsingSkipsDeadAndCopyModePanes() {
        let output = "%1\tclaude\t0\t0\n%2\tzsh\t0\t0\n%3\tcodex\t1\t0\n%4\tnode\t0\t1\ngarbage\n"
        #expect(TmuxCommands.parsePanes(output) == [.init(id: "%1", command: "claude"), .init(id: "%2", command: "zsh")])
        #expect(TmuxCommands.typeContinue("%1") == ["send-keys", "-t", "%1", "-l", "continue"])
        #expect(TmuxCommands.pressEnter("%1") == ["send-keys", "-t", "%1", "Enter"])
        #expect(TmuxCommands.hash("abc") == TmuxCommands.hash("abc") && TmuxCommands.hash("abc") != TmuxCommands.hash("abd"))
    }
}

@Suite struct InsomniaFreezePolicyTests {
    @Test func neverZeusTerminalsOrAgents() {
        let running: [InsomniaFreezePolicy.RunningProcess] = [
            .init(pid: 100, bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            .init(pid: 4242, bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            .init(pid: 200, bundleID: "app.zeus.mac", name: "Zeus"),
            .init(pid: 300, bundleID: "com.googlecode.iterm2", name: "iTerm2"),
            .init(pid: 400, bundleID: "com.example.wrapper", name: "claude"),
            .init(pid: 500, bundleID: "com.hnc.Discord", name: "Discord"),
        ]
        let listed = ["com.tinyspeck.slackmacgap", "app.zeus.mac", "com.googlecode.iterm2", "com.example.wrapper", "com.hnc.Discord"]
        let targets = InsomniaFreezePolicy.targets(listed: listed, running: running, zeusPID: 4242)
        #expect(targets.map(\.pid) == [100, 500])
        #expect(InsomniaFreezePolicy.isProtected(bundleID: "com.apple.Terminal"))
        #expect(!InsomniaFreezePolicy.isProtected(bundleID: "com.hnc.Discord"))
    }
}

@Suite struct InsomniaDurationTests {
    @Test func typedStepsAndChips() {
        var duration = InsomniaDuration(hours: 1, minutes: 0)
        #expect(duration.totalMinutes == 60 && duration.label == "1 h")
        duration.type(minutes: "90")
        #expect(duration.hours == 2 && duration.minutes == 30 && duration.label == "2 h 30 m")
        duration.type(hours: "0x4")
        #expect(duration.hours == 4)
        duration.step(minutes: -5)
        #expect(duration.hours == 4 && duration.minutes == 25)
        duration.step(hours: -10)
        #expect(duration.totalMinutes == 1) // never under a minute
        duration.apply(chip: nil)
        #expect(duration.totalMinutes == nil && duration.label == "∞")
        duration.step(minutes: 5)
        #expect(!duration.indefinite)
        duration.apply(chip: 480)
        #expect(duration.totalMinutes == 480)
        duration.type(hours: "999")
        #expect(duration.hours == InsomniaDuration.maxHours && duration.minutes == 0)
        #expect(InsomniaDuration.chips.map(InsomniaDuration.chipLabel) == ["30 m", "1 h", "2 h", "4 h", "8 h", "∞"])
    }

    @Test func untilAClockTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 21, minute: 15))!
        #expect(InsomniaDuration.minutes(until: 23, 30, from: now, calendar: calendar) == 135)
        // Earlier on the clock means tomorrow.
        #expect(InsomniaDuration.minutes(until: 7, 0, from: now, calendar: calendar) == 9 * 60 + 45)
        #expect(InsomniaDuration.parseClock("23:30")! == (23, 30))
        #expect(InsomniaDuration.parseClock("7:05")! == (7, 5))
        #expect(InsomniaDuration.parseClock("24:00") == nil)
        #expect(InsomniaDuration.parseClock("7:5") == nil)
        #expect(InsomniaDuration.parseClock("soon") == nil)
    }
}

@Suite struct InsomniaTabTests {
    @Test func defaultTabOrder() {
        #expect(TopBarLayout.defaultRow == [.home, .chat, .notifications, .clipboard, .shelf, .todo, .dictation, .teleprompter, .insomnia, .polyglot, .recordly, .scribe])
        #expect(Array(TopBarLayout.standard.tabs.prefix(12)) == TopBarLayout.defaultRow)
        #expect(GlanceTabRow.visible(TopBarLayout.standard.tabs, selected: .home) == TopBarLayout.defaultRow)
        #expect(TopBarTab.insomnia.title == "Insomnia")
        #expect(TopBarTab.insomnia.symbol == "moon.zzz.fill")
        #expect(TopBarTab.insomnia.help == "Insomnia: keep working with the lid closed")
        #expect(TopBarTab.teleprompter.help == TopBarTab.teleprompter.title)
    }

    @Test func savedLayoutsUpgradeToTheNineTabRow() {
        // Tony's older saved layout: Glance's seven, the rest, Teleprompter far down, no Insomnia.
        let old = TopBarLayout(tabs: [.home, .chat, .notifications, .clipboard, .shelf, .todo, .dictation, .reminders, .today, .music, .teleprompter, .usage])
        #expect(old.upgradedToNineTabRow().tabs == [.home, .chat, .notifications, .clipboard, .shelf, .todo, .dictation, .teleprompter, .insomnia, .reminders, .today, .music, .usage])
        // A tab turned off (Clipboard) stays off.
        let custom = TopBarLayout(tabs: [.home, .shelf, .chat])
        #expect(custom.upgradedToNineTabRow().tabs == [.home, .chat, .shelf, .teleprompter, .insomnia])
    }

    @Test func insomniaAppearsInLayoutsSavedBeforeIt() {
        let knownBefore = #"["home","today","agents","chat","notifications","music","calendar","todo","reminders","weather","clipboard","shelf","focus","dictation","teleprompter","usage"]"#
        let layout = TopBarLayout.decode(#"["home","chat","teleprompter"]"#, known: knownBefore)
        #expect(layout.contains(.insomnia))
    }
}
