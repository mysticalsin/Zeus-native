import Foundation
import Testing
@testable import ZeusCore

@Suite("Usage limits")
struct UsageLimitsTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ string: String) -> Date { parseISODate(string)! }

    func claudeLine(id: String, request: String = "r", at time: String, model: String = "claude-opus-5-5", input: Int = 10, output: Int = 20, write: Int = 0, read: Int = 0) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"\#(request)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(write),"cache_read_input_tokens":\#(read)}}}"#
    }

    @Test func claudeParserReadsUsageAndDropsDuplicates() {
        let text = [
            claudeLine(id: "m1", at: "2026-10-31T10:05:00.000Z", input: 2, output: 3, write: 100, read: 1000),
            claudeLine(id: "m1", at: "2026-10-31T10:05:00.000Z", input: 2, output: 3, write: 100, read: 1000),
            #"{"type":"user","timestamp":"2026-10-31T10:04:00.000Z","message":{"role":"user","content":"hi"}}"#,
            claudeLine(id: "m2", at: "2026-10-31T10:06:00Z", model: "<synthetic>"),
            "not json",
        ].joined(separator: "\n")
        var seen = Set<String>()
        let entries = ClaudeUsageParser.entries(from: text, seen: &seen)
        #expect(entries.count == 1)
        #expect(entries[0].total == 1105)
        #expect(entries[0].model == "claude-opus-5-5")
        #expect(ClaudeUsageParser.entries(from: text, seen: &seen).isEmpty)
    }

    @Test func codexParserReadsLimitsAndSkipsRepeatedTotals() {
        let text = #"""
        {"timestamp":"2026-10-26T00:40:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5-codex"}}
        {"timestamp":"2026-10-26T00:41:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500},"last_token_usage":{"input_tokens":400,"cached_input_tokens":300,"output_tokens":100}},"rate_limits":null}}
        {"timestamp":"2026-10-26T00:42:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":500},"last_token_usage":{"input_tokens":400,"cached_input_tokens":300,"output_tokens":100}},"rate_limits":{"primary":{"used_percent":32.0,"window_minutes":10080,"resets_at":1793513493},"secondary":null,"plan_type":"pro"}}}
        """#
        let result = CodexUsageParser.parse(text)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].input == 100)
        #expect(result.entries[0].cacheRead == 300)
        #expect(result.entries[0].model == "gpt-5.5-codex")
        #expect(result.limits?.primary == RateWindow(usedPercent: 32, windowMinutes: 10_080, resetsAt: Date(timeIntervalSince1970: 1_793_513_493)))
        #expect(result.limits?.primary?.label == "Weekly")
        #expect(result.limits?.plan == "pro")
    }

    @Test func blocksStartOnTheHourAndLastFiveHours() {
        let entries = ["2026-10-31T09:47:00Z", "2026-10-31T13:59:00Z", "2026-10-31T14:00:00Z", "2026-10-31T22:10:00Z"].map {
            UsageEntry(provider: .claude, date: date($0), model: "opus", input: 1, output: 1)
        }
        let blocks = UsageBlock.blocks(entries, calendar: utc)
        #expect(blocks.count == 3)
        #expect(blocks[0].start == date("2026-10-31T09:00:00Z"))
        #expect(blocks[0].end == date("2026-10-31T14:00:00Z"))
        #expect(blocks[0].entries.count == 2)
        #expect(blocks[1].start == date("2026-10-31T14:00:00Z"))
        #expect(blocks[2].start == date("2026-10-31T22:00:00Z"))
    }

    @Test func claudeMeterComparesWithBusiestPastWindow() {
        let entries = [
            UsageEntry(provider: .claude, date: date("2026-10-30T08:00:00Z"), model: "claude-opus-5-5", input: 1000, output: 0),
            UsageEntry(provider: .claude, date: date("2026-10-31T10:30:00Z"), model: "claude-sonnet-5-5", input: 250, output: 0),
            UsageEntry(provider: .codex, date: date("2026-10-31T10:30:00Z"), model: "codex", input: 99_999, output: 0),
        ]
        let now = date("2026-10-31T11:00:00Z")
        let usage = UsageSummary.make(provider: .claude, entries: entries, now: now, calendar: utc)
        let fiveHour = usage.meters[0]
        #expect(fiveHour.label == "5h")
        #expect(fiveHour.fraction == 0.25)
        #expect(fiveHour.tokens == 250)
        #expect(fiveHour.resetsAt == date("2026-10-31T15:00:00Z"))
        #expect(usage.todayTokens == 250)
        #expect(usage.weekTokens == 1250)
        #expect(usage.daily == [0, 0, 0, 0, 0, 1000, 250])
        #expect(usage.topModel == "claude-opus-5-5")
        #expect(usage.tightest?.label == "5h")
        #expect(usage.plan == nil)

        let capped = UsageSummary.make(provider: .claude, entries: entries, blockLimit: 200, now: now, calendar: utc)
        #expect(capped.meters[0].fraction == 1)
    }

    @Test func idleClaudeWindowReadsZero() {
        let entries = [UsageEntry(provider: .claude, date: date("2026-10-31T01:00:00Z"), model: "opus", input: 10, output: 0)]
        let usage = UsageSummary.make(provider: .claude, entries: entries, now: date("2026-10-31T11:00:00Z"), calendar: utc)
        #expect(usage.meters[0].fraction == 0)
        #expect(usage.meters[0].resetsAt == nil)
    }

    @Test func codexMeterUsesReportedLimitsAndExpiresPastResets() {
        let now = date("2026-10-31T11:00:00Z")
        let limits = CodexLimits(date: now,
                                 primary: RateWindow(usedPercent: 80, windowMinutes: 300, resetsAt: now.addingTimeInterval(600)),
                                 secondary: RateWindow(usedPercent: 40, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(-60)),
                                 plan: "plus")
        let usage = UsageSummary.make(provider: .codex, entries: [], codexLimits: limits, now: now, calendar: utc)
        #expect(usage.meters.map(\.label) == ["5h", "Weekly"])
        #expect(usage.meters[0].fraction == 0.8)
        #expect(usage.meters[0].estimated == false)
        #expect(usage.meters[1].fraction == 0)
        #expect(usage.tightest?.label == "5h")
        #expect(usage.plan == "plus")
        #expect(usage.hasData)
    }

    @Test func pricingMatchesFamilies() {
        let pricing = UsagePricing.standard
        let entry = UsageEntry(provider: .claude, date: Date(), model: "claude-sonnet-5-5", input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 1_000_000)
        #expect(abs(pricing.cost(entry) - 18.3) < 0.0001)
        #expect(pricing.price(for: "mystery-model") == nil)
    }

    @Test func formatting() {
        #expect(UsageSummary.compact(980) == "980")
        #expect(UsageSummary.compact(34_200) == "34.2k")
        #expect(UsageSummary.compact(340_000) == "340k")
        #expect(UsageSummary.compact(1_250_000) == "1.2M")
        #expect(UsageSummary.compact(8_672_000_000) == "8.7B")
        let now = date("2026-10-31T11:00:00Z")
        #expect(UsageSummary.countdown(to: now.addingTimeInterval(2 * 3600 + 300), from: now) == "2h 05m")
        #expect(UsageSummary.countdown(to: now.addingTimeInterval(720), from: now) == "12m")
        #expect(UsageSummary.countdown(to: now.addingTimeInterval(3 * 86_400 + 7200), from: now) == "3d 2h")
        #expect(UsageSummary.countdown(to: now, from: now) == "now")
    }

    @Test func scannerReadsRecentFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        try (claudeLine(id: "a", at: stamp) + "\n").write(to: project.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        var scanner = UsageScanner(home: home)
        scanner.claudeRoots = [home.appendingPathComponent(".claude/projects")]
        let snapshot = scanner.scan(now: now)
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.codexLimits == nil)

        // Appended lines are picked up on the next scan; a half-written line waits.
        let handle = try FileHandle(forWritingTo: project.appendingPathComponent("s.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((claudeLine(id: "b", at: stamp) + "\n" + #"{"type":"assist"#).utf8))
        try handle.close()
        #expect(scanner.scan(now: now).entries.count == 2)
        #expect(scanner.scan(now: now).entries.count == 2)
    }

    @Test func targetedScanSkipsTheWalk() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))
        let first = project.appendingPathComponent("s.jsonl")
        try (claudeLine(id: "a", at: stamp) + "\n").write(to: first, atomically: true, encoding: .utf8)
        var scanner = UsageScanner(home: home)
        scanner.claudeRoots = [home.appendingPathComponent(".claude/projects")]
        #expect(scanner.scan(now: now).entries.count == 1)
        // Idle: the watcher saw nothing, so only the known file is checked and nothing changes.
        #expect(scanner.scan(now: now, changed: []).unchanged)
        // A new session file the watcher reported is picked up without walking the folder.
        let second = project.appendingPathComponent("t.jsonl")
        try (claudeLine(id: "b", at: stamp) + "\n").write(to: second, atomically: true, encoding: .utf8)
        #expect(scanner.scan(now: now, changed: [second]).entries.count == 2)
        #expect(scanner.walkCounts.full == 1)
        #expect(scanner.walkCounts.targeted == 2)
    }
}


@Suite("Fast ISO dates")
struct FastISODateTests {
    @Test func matchesFormatter() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for text in ["2026-10-31T18:20:05.123Z", "2024-02-29T00:00:00.000Z", "1999-12-31T23:59:59.999Z"] {
            let fast = fastUTCDate(text)!.timeIntervalSince1970
            #expect(abs(fast - formatter.date(from: text)!.timeIntervalSince1970) < 0.0005)
        }
        #expect(fastUTCDate("2026-10-31T18:20:05Z")!.timeIntervalSince1970 == ISO8601DateFormatter().date(from: "2026-10-31T18:20:05Z")!.timeIntervalSince1970)
        #expect(fastUTCDate("2026-10-31T18:20:05+02:00") == nil)
    }

    @Test func slimKeepsUsage() {
        let big = String(repeating: "x", count: 5000)
        let line = #"{"parentUuid":"p","message":{"model":"claude-x","id":"msg_1","type":"message","content":[{"type":"text","text":"\#(big) "usage":{"input_tokens":999}"}],"usage":{"input_tokens":2,"output_tokens":7,"cache_read_input_tokens":3,"cache_creation_input_tokens":4,"output_tokens_details":{"thinking_tokens":1},"service_tier":"standard"}},"requestId":"req_9","type":"assistant","uuid":"u","timestamp":"2026-10-31T18:20:05.123Z"}"#
        let parsed = ClaudeUsageParser.parse(line: Data(line.utf8))
        #expect(parsed?.entry.input == 2)
        #expect(parsed?.entry.output == 7)
        #expect(parsed?.entry.model == "claude-x")
        #expect(parsed?.key == "msg_1:req_9")
    }
}

@Suite("Brain today")
struct BrainTodayTests {
    @Test func ranksTodayAndPriorityAndSkipsBlocked() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brain-\(UUID().uuidString)")
        let project = root.appendingPathComponent("01_Projects/Soul", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("_agent_state"), withIntermediateDirectories: true)
        try "- [ ] hidden\n".write(to: root.appendingPathComponent("_agent_state/x.md"), atomically: true, encoding: .utf8)
        try """
        - [ ] TASK-0001 Low thing #todo #priority/low
        - [x] Done thing
        - [ ] TASK-0002 Big thing #todo #priority/high
        - [ ] Blocked thing #blocked
        - [ ] Call Anna 📅 2026-10-31
        """.write(to: project.appendingPathComponent("01 - Tasks.md"), atomically: true, encoding: .utf8)
        var parts = DateComponents(); parts.year = 2026; parts.month = 10; parts.day = 31; parts.hour = 12
        let today = Calendar(identifier: .gregorian).date(from: parts)!
        let tasks = BrainToday.scan(root: root, today: today)
        #expect(tasks.map(\.title) == ["Call Anna", "Big thing", "Low thing"])
        #expect(tasks.first?.dueToday == true)
        #expect(tasks.first?.project == "Soul")
    }
}
