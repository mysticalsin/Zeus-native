import Foundation

public struct SilentEvalScenarioResult: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var notes: String
    public var seconds: Double
    public var llmCalls: Int

    public init(id: String, ok: Bool, notes: String, seconds: Double = 0, llmCalls: Int = 0) {
        self.id = id
        self.ok = ok
        self.notes = notes
        self.seconds = seconds
        self.llmCalls = llmCalls
    }
}

public struct SilentEvalReport: Codable, Equatable, Sendable {
    public var generated: Date
    public var pass: Bool
    public var scenarios: [SilentEvalScenarioResult]

    public init(generated: Date = Date(), pass: Bool, scenarios: [SilentEvalScenarioResult]) {
        self.generated = generated
        self.pass = pass
        self.scenarios = scenarios
    }
}

public enum SilentEvalHarness {
    public static let minimumScenarios = 15

    public static func runAll() -> SilentEvalReport {
        let started = Date()
        var rows: [SilentEvalScenarioResult] = []
        rows.append(run("fast_open_safari") {
            guard case .openApp(let name, _) = FastIntent.parse("open Safari") else { return "expected openApp" }
            return name.lowercased() == "safari" ? nil : "wrong app \(name)"
        })
        rows.append(run("fast_mute_volume") {
            guard case .volume(.mute) = FastIntent.parse("mute") else { return "expected mute" }
            return nil
        })
        rows.append(run("fast_timer_90") {
            guard case .timer(let seconds) = FastIntent.parse("90 second timer") else { return "expected timer" }
            return seconds == 90 ? nil : "wrong seconds \(seconds)"
        })
        rows.append(run("fast_lock_screen") {
            guard case .lockScreen = FastIntent.parse("lock screen") else { return "expected lock" }
            return nil
        })
        rows.append(run("fake_shell_test") {
            let mac = FakeMacSnapshot(shellTests: ["test -f /tmp/zeus-build.done": true])
            let watch = ZeusWatch(label: "build", trigger: .shellTest(exitZeroWhen: "test -f /tmp/zeus-build.done"))
            let result = ZeusWatchEvaluator.evaluate(watch, mac: mac)
            return result.fired ? nil : "shell test did not fire"
        })
        rows.append(run("watch_window_gone") {
            let watch = ZeusWatch(label: "xcode", trigger: .windowGone(titleContains: "Building"))
            var llm = 0
            let states = [
                FakeMacSnapshot(frontWindowTitle: "Building Zeus"),
                FakeMacSnapshot(frontWindowTitle: "Building Zeus"),
                FakeMacSnapshot(frontWindowTitle: "Ready"),
            ]
            let (fired, ticks) = ZeusWatchEvaluator.pollUntilFire(watch: watch, macStates: states, llmCalls: &llm)
            if llm != 0 { return "LLM calls while waiting" }
            return fired && ticks <= 3 ? nil : "watch did not fire quickly"
        })
        rows.append(run("memory_remember_metric") {
            var store = UserMemoryStore()
            guard case .storedRule = store.rememberRule("I prefer metric units") else { return "remember failed" }
            let block = store.promptBlock(for: "how far is the moon")
            return block.localizedCaseInsensitiveContains("metric") ? nil : "rule missing from prompt"
        })
        rows.append(run("memory_forget") {
            var store = UserMemoryStore()
            _ = store.rememberRule("I prefer tea")
            let removed = store.forget(matching: "tea")
            return removed == 1 && store.rules.isEmpty ? nil : "forget failed"
        })
        rows.append(run("memory_blocks_sensitive") {
            var store = UserMemoryStore()
            let card = "my card is 4111 1111 1111 1111"
            guard case .rejectedScreenSource = store.learnFromScreen(card) else { return "screen learn should fail" }
            guard case .rejectedSensitive = store.rememberFact(card) else { return "card should not store" }
            return store.facts.isEmpty && store.rules.isEmpty ? nil : "sensitive data stored"
        })
        rows.append(run("memory_command_parse") {
            guard let cmd = UserMemoryCommands.parse("remember I prefer metric") else { return "parse failed" }
            guard case .remember(let text) = cmd.kind, text.contains("metric") else { return "wrong remember text" }
            guard UserMemoryCommands.parse("forget that") != nil else { return "forget parse failed" }
            return nil
        })
        rows.append(run("routine_weekday_schedule") {
            guard let parsed = RoutineVoiceParse.parse("every weekday at 8, summarize my calendar") else { return "voice parse failed" }
            return parsed.schedule.days == .weekdays && parsed.schedule.hour == 8 ? nil : "bad schedule"
        })
        rows.append(run("routine_relaunch_guard") {
            var guardState = RoutineRelaunchGuard()
            let routine = Routine(name: "Brief", prompt: "hi", schedule: .init(days: .daily, hour: 8, minute: 0), created: Date())
            let slot = Date(timeIntervalSince1970: 1_700_000_000)
            guard guardState.shouldRun(routine: routine, scheduled: slot) else { return "first run blocked" }
            guardState.markRan(routineID: routine.id, scheduled: slot)
            return guardState.shouldRun(routine: routine, scheduled: slot) ? "duplicate slot allowed" : nil
        })
        rows.append(run("launchd_plist_shape") {
            let routine = Routine(name: "Brief", prompt: "p", schedule: .init(days: .weekdays, hour: 8, minute: 30), created: Date())
            let plist = RoutineLaunchAgent.plist(routine: routine, zeusBinary: "/tmp/zeus")
            guard plist["StartCalendarInterval"] != nil else { return "missing interval" }
            guard (plist["ProgramArguments"] as? [String])?.contains("routine-run") == true else { return "bad args" }
            return nil
        })
        rows.append(run("background_move_threshold") {
            let start = Date(timeIntervalSince1970: 0)
            let early = Date(timeIntervalSince1970: 10)
            let late = Date(timeIntervalSince1970: 20)
            if BackgroundAgentCoordinator.shouldMoveToBackground(started: start, now: early) { return "moved too early" }
            return BackgroundAgentCoordinator.shouldMoveToBackground(started: start, now: late) ? nil : "should move at 20s"
        })
        rows.append(run("background_steer_session") {
            var session = BackgroundAgentSession(title: "Hub")
            let id = session.id
            session.steer("check HDMI too")
            guard session.id == id, session.steerMessages.count == 1 else { return "steer broke session" }
            return nil
        })
        rows.append(run("meeting_fixture_transcript") {
            let fixture = """
            We agreed to ship in March.
            The budget is four hundred thousand.
            """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-meeting-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: url) }
            try? fixture.write(to: url, atomically: true, encoding: .utf8)
            guard let transcript = try? MeetingCopilotEngine.transcribeFixture(at: url), transcript.lines.count >= 2 else { return "transcript missing" }
            return transcript.lines[0].start == 0 ? nil : "missing timestamps"
        })
        rows.append(run("meeting_answer_budget") {
            let transcript = MeetingTranscript(lines: [
                MeetingTranscriptLine(start: 0, speaker: "Them", text: "The budget is four hundred thousand."),
            ])
            let answer = transcript.answer(question: "What did they say about budget?")
            return answer.localizedCaseInsensitiveContains("budget") ? nil : "answer missed budget"
        })
        rows.append(run("meeting_archive_mode") {
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-archive-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }
                let archive = MeetingArchive(url: dir.appendingPathComponent("events.jsonl"))
                try archive.append(.init(date: Date(), kind: "transcript", detail: "ok"))
                let attrs = try FileManager.default.attributesOfItem(atPath: archive.url.path)
                let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
                return mode == 0o600 ? nil : "expected 0600, got \(String(describing: mode))"
            } catch {
                return "error: \(error)"
            }
        })
        rows.append(run("agent_steer_parse") {
            guard let msg = BackgroundAgentCoordinator.parseSteer("tell the hub agent to check HDMI too") else { return "steer parse failed" }
            return msg.localizedCaseInsensitiveContains("hdmi") ? nil : "wrong steer text"
        })
        rows.append(run("routine_due_once") {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let now = ISO8601DateFormatter().date(from: "2026-10-30T10:00:00Z")!
            let morning = Routine(name: "Brief", prompt: "Summarize my day", schedule: .init(days: .daily, hour: 7, minute: 0),
                                  created: ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!,
                                  lastRun: ISO8601DateFormatter().date(from: "2026-10-29T07:00:00Z")!)
            let due = RoutinePlanner.due([morning], now: now, calendar: utc)
            return due.count == 1 ? nil : "expected one due routine"
        })
        _ = started
        let pass = rows.allSatisfy(\.ok) && rows.count >= minimumScenarios
        return SilentEvalReport(pass: pass, scenarios: rows)
    }

    private static func run(_ id: String, _ body: () throws -> String?) -> SilentEvalScenarioResult {
        let t0 = Date()
        do {
            if let problem = try body() {
                return SilentEvalScenarioResult(id: id, ok: false, notes: problem, seconds: Date().timeIntervalSince(t0))
            }
            return SilentEvalScenarioResult(id: id, ok: true, notes: "ok", seconds: Date().timeIntervalSince(t0))
        } catch {
            return SilentEvalScenarioResult(id: id, ok: false, notes: "error: \(error)", seconds: Date().timeIntervalSince(t0))
        }
    }
}
