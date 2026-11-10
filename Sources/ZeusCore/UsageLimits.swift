import Foundation

/// Coding agents whose usage ZEUS reads from their own local logs. Nothing is fetched from
/// the network and no credentials are read.
public enum UsageProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: String { rawValue }
    public var title: String { self == .claude ? "Claude Code" : "Codex" }
}

/// Tokens of one model response.
extension Array {
    /// True when the elements are already in ascending order by `key` (one linear pass).
    func isSorted<T: Comparable>(by key: (Element) -> T) -> Bool {
        guard count > 1 else { return true }
        var previous = key(self[0])
        for element in dropFirst() {
            let next = key(element)
            if next < previous { return false }
            previous = next
        }
        return true
    }
}

public struct UsageEntry: Equatable, Sendable {
    public var provider: UsageProvider
    public var date: Date
    public var model: String
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(provider: UsageProvider, date: Date, model: String, input: Int, output: Int, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.provider = provider
        self.date = date
        self.model = model
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var total: Int { input + output + cacheWrite + cacheRead }
}

/// A limit the provider itself reports (Codex writes these into its session logs).
public struct RateWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    /// "5h", "Weekly", or the window in hours.
    public var label: String {
        switch windowMinutes {
        case 300: "5h"
        case 10_080: "Weekly"
        case let minutes where minutes % 1440 == 0: "\(minutes / 1440)d"
        default: "\(max(windowMinutes / 60, 1))h"
        }
    }
}

public struct CodexLimits: Equatable, Sendable {
    public var date: Date
    public var primary: RateWindow?
    public var secondary: RateWindow?
    public var plan: String?

    public init(date: Date, primary: RateWindow?, secondary: RateWindow?, plan: String?) {
        self.date = date
        self.primary = primary
        self.secondary = secondary
        self.plan = plan
    }

    public var windows: [RateWindow] { [primary, secondary].compactMap { $0 } }
}

// MARK: Parsing

// ISO8601DateFormatter is documented thread-safe for parsing.
nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

nonisolated(unsafe) private let isoFormatterPlain = ISO8601DateFormatter()

func parseISODate(_ string: String?) -> Date? {
    guard let string else { return nil }
    if let fast = fastUTCDate(string) { return fast }
    return isoFormatter.date(from: string) ?? isoFormatterPlain.date(from: string)
}

/// `YYYY-MM-DDTHH:MM:SS[.fff]Z` without ICU: the logs hold millions of these, and
/// ISO8601DateFormatter made the first usage scan pin a core for minutes.
func fastUTCDate(_ string: String) -> Date? {
    let b = Array(string.utf8)
    guard b.count >= 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58, b.last == 90 else { return nil }
    func num(_ from: Int, _ count: Int) -> Int? {
        var value = 0
        for i in from..<from + count { let d = Int(b[i]) - 48; guard (0...9).contains(d) else { return nil }; value = value * 10 + d }
        return value
    }
    guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2), let s = num(17, 2),
          (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61 else { return nil }
    var fraction = 0.0
    if b[19] == 46 {
        var scale = 0.1
        var i = 20
        while i < b.count - 1 { let digit = Int(b[i]) - 48; guard (0...9).contains(digit) else { return nil }; fraction += Double(digit) * scale; scale /= 10; i += 1 }
    } else if b.count != 20 { return nil }
    // Days from civil (Howard Hinnant).
    let yy = mo <= 2 ? y - 1 : y
    let era = (yy >= 0 ? yy : yy - 399) / 400
    let yoe = yy - era * 400
    let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146_097 + doe - 719_468
    return Date(timeIntervalSince1970: Double(days * 86_400 + h * 3600 + mi * 60 + s) + fraction)
}

/// Walks newline-separated JSON without turning the file into a String: logs reach hundreds
/// of megabytes, and only a few lines in each carry usage.
public enum JSONLines {
    /// Calls `body` with each complete line that contains one of `markers` (within the first
    /// `prefixLimit` bytes when given). Returns the offset just past the last complete line.
    @discardableResult
    public static func forEach(_ data: Data, markers: [String], prefixLimit: Int? = nil, _ body: (Data) -> Void) -> Int {
        let needles = markers.map { Array($0.utf8) }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress, raw.count > 0 else { return 0 }
            var start = 0
            while start < raw.count {
                guard let newline = memchr(base + start, 0x0A, raw.count - start) else { break }
                let end = base.distance(to: UnsafeRawPointer(newline))
                let length = end - start
                let searchLength = min(length, prefixLimit ?? length)
                let hit = needles.contains { needle in
                    searchLength >= needle.count
                        && needle.withUnsafeBytes { memmem(base + start, searchLength, $0.baseAddress, needle.count) } != nil
                }
                if hit {
                    body(Data(bytes: base + start, count: length))
                }
                start = end + 1
            }
            return start
        }
    }
}

/// Claude Code session transcripts (`~/.claude/projects/<project>/<session>.jsonl`).
public enum ClaudeUsageParser {
    /// One assistant line → its usage and a key to drop the copies Claude Code writes when
    /// a response is split across several lines or a session is resumed.
    public static func parse(line: Data) -> (key: String, entry: UsageEntry)? {
        // Assistant lines carry whole tool outputs (often hundreds of KB); parse only the few
        // fields we need so the first scan of gigabytes of logs stays cheap.
        let source = line.count > 2048 ? (slim(line) ?? line) : line
        guard let object = try? JSONSerialization.jsonObject(with: source) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let date = parseISODate(object["timestamp"] as? String) else { return nil }
        let model = message["model"] as? String ?? "unknown"
        guard model != "<synthetic>" else { return nil }
        let entry = UsageEntry(provider: .claude, date: date, model: model,
                               input: usage["input_tokens"] as? Int ?? 0,
                               output: usage["output_tokens"] as? Int ?? 0,
                               cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
                               cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0)
        let key = "\(message["id"] as? String ?? UUID().uuidString):\(object["requestId"] as? String ?? "")"
        return (key, entry)
    }

    /// `{"type","timestamp","requestId","message":{"id","model","usage"}}` cut straight from the
    /// bytes. JSON strings escape their quotes, so `"usage":{` etc. only match real keys.
    static func slim(_ line: Data) -> Data? {
        let bytes = [UInt8](line)
        func find(_ needle: String, from: Int = 0, last: Bool = false) -> Int? {
            let n = Array(needle.utf8)
            guard bytes.count >= n.count, from <= bytes.count - n.count else { return nil }
            if last {
                var i = bytes.count - n.count
                while i >= from { if bytes[i] == n[0] && Array(bytes[i..<i + n.count]) == n { return i + n.count }; i -= 1 }
                return nil
            }
            var i = from
            while i <= bytes.count - n.count { if bytes[i] == n[0] && Array(bytes[i..<i + n.count]) == n { return i + n.count }; i += 1 }
            return nil
        }
        func string(after key: String, from: Int = 0, last: Bool = false) -> String? {
            guard let start = find("\"\(key)\":\"", from: from, last: last) else { return nil }
            var i = start
            while i < bytes.count, bytes[i] != 0x22 { i += bytes[i] == 0x5C ? 2 : 1 }
            guard i <= bytes.count else { return nil }
            return String(decoding: bytes[start..<min(i, bytes.count)], as: UTF8.self)
        }
        guard find("\"type\":\"assistant\"") != nil,
              let message = find("\"message\":{"),
              let usageStart = find("\"usage\":{", from: message, last: true) else { return nil }
        var depth = 1, i = usageStart, inString = false
        while i < bytes.count, depth > 0 {
            let b = bytes[i]
            if inString { if b == 0x5C { i += 1 } else if b == 0x22 { inString = false } }
            else if b == 0x22 { inString = true } else if b == 0x7B { depth += 1 } else if b == 0x7D { depth -= 1 }
            i += 1
        }
        guard depth == 0 else { return nil }
        let usage = String(decoding: bytes[(usageStart - 1)..<i], as: UTF8.self)
        func quoted(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        let text = "{\"type\":\"assistant\",\"timestamp\":\(quoted(string(after: "timestamp", from: i, last: true))),"
            + "\"requestId\":\(quoted(string(after: "requestId", from: i, last: true) ?? string(after: "requestId", last: true))),"
            + "\"message\":{\"id\":\(quoted(string(after: "id", from: message))),\"model\":\(quoted(string(after: "model", from: message))),"
            + "\"usage\":\(usage)}}"
        return Data(text.utf8)
    }

    /// Keyed entries of every complete line in `data`, and where the next read should start.
    static func scan(_ data: Data) -> (items: [(key: String, entry: UsageEntry)], consumed: Int) {
        var items: [(key: String, entry: UsageEntry)] = []
        let consumed = JSONLines.forEach(data, markers: ["\"usage\""]) { line in
            if let parsed = parse(line: line) { items.append(parsed) }
        }
        return (items, consumed)
    }

    public static func entries(from text: String, seen: inout Set<String>) -> [UsageEntry] {
        scan(Data((text + "\n").utf8)).items.compactMap { seen.insert($0.key).inserted ? $0.entry : nil }
    }
}

/// Codex rollout logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
public enum CodexUsageParser {
    public struct Result: Equatable, Sendable {
        public var entries: [UsageEntry] = []
        public var limits: CodexLimits?
        /// Carried across incremental reads of a growing file.
        var model = "codex"
        var lastTotal: Int?
    }

    public static func parse(_ text: String) -> Result {
        var result = Result()
        _ = parse(Data((text + "\n").utf8), into: &result)
        return result
    }

    /// The markers sit in the first bytes of each line, so huge transcript lines are skipped
    /// without being searched. Returns where the next read should start.
    static func parse(_ data: Data, into result: inout Result) -> Int {
        JSONLines.forEach(data, markers: ["\"token_count\"", "\"turn_context\""], prefixLimit: 160) { line in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { return }
            if object["type"] as? String == "turn_context", let name = payload["model"] as? String {
                result.model = name
                return
            }
            guard payload["type"] as? String == "token_count", let date = parseISODate(object["timestamp"] as? String) else { return }
            if let info = payload["info"] as? [String: Any],
               let last = info["last_token_usage"] as? [String: Any],
               let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int,
               total != result.lastTotal {
                // Codex repeats the same count on every rate-limit refresh; only a new total is new work.
                result.lastTotal = total
                let cached = last["cached_input_tokens"] as? Int ?? 0
                let input = max((last["input_tokens"] as? Int ?? 0) - cached, 0)
                let output = last["output_tokens"] as? Int ?? 0
                if input + output + cached > 0 {
                    result.entries.append(UsageEntry(provider: .codex, date: date, model: result.model, input: input, output: output, cacheRead: cached))
                }
            }
            if let limits = payload["rate_limits"] as? [String: Any] {
                let snapshot = CodexLimits(date: date, primary: window(limits["primary"]), secondary: window(limits["secondary"]),
                                           plan: limits["plan_type"] as? String)
                if !snapshot.windows.isEmpty { result.limits = snapshot }
            }
        }
    }

    static func window(_ value: Any?) -> RateWindow? {
        guard let value = value as? [String: Any], let used = (value["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (value["window_minutes"] as? NSNumber)?.intValue ?? 0
        let resets = (value["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resets)
    }
}

// MARK: Windows

/// Claude plans meter use in 5-hour windows that start with your first message. ZEUS
/// rebuilds them from the transcripts: a window opens at the hour of the first message
/// after the previous one closed.
public struct UsageBlock: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var entries: [UsageEntry]

    public var tokens: Int { entries.reduce(0) { $0 + $1.total } }
    public var lastActivity: Date? { entries.last?.date }
    public func isActive(at now: Date) -> Bool { now >= start && now < end }

    public static let length: TimeInterval = 5 * 3600

    public static func blocks(_ entries: [UsageEntry], calendar: Calendar = .current) -> [UsageBlock] {
        var blocks: [UsageBlock] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if let last = blocks.indices.last, entry.date < blocks[last].end {
                // In place: copying the block out and back made this O(n²) (seconds of main-thread CPU a minute).
                blocks[last].entries.append(entry)
            } else {
                let start = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                blocks.append(UsageBlock(start: start, end: start.addingTimeInterval(length), entries: [entry]))
            }
        }
        return blocks
    }
}

/// API list prices per million tokens, used only for an "API equivalent" estimate.
/// Matched by the first family name the model id contains. Edit here when prices change.
public struct UsagePricing: Sendable {
    public struct Price: Equatable, Sendable {
        public var input: Double
        public var output: Double
        public var cacheWrite: Double
        public var cacheRead: Double

        public init(input: Double, output: Double, cacheWrite: Double? = nil, cacheRead: Double? = nil) {
            self.input = input
            self.output = output
            self.cacheWrite = cacheWrite ?? input * 1.25
            self.cacheRead = cacheRead ?? input * 0.1
        }
    }

    public var families: [(match: String, price: Price)]

    public static let standard = UsagePricing(families: [
        ("opus", Price(input: 5, output: 25)),
        ("sonnet", Price(input: 3, output: 15)),
        ("haiku", Price(input: 1, output: 5)),
        ("codex", Price(input: 1.25, output: 10, cacheWrite: 1.25, cacheRead: 0.125)),
        ("gpt-5", Price(input: 1.25, output: 10, cacheWrite: 1.25, cacheRead: 0.125)),
    ])

    public func price(for model: String) -> Price? {
        let id = model.lowercased()
        return families.first { id.contains($0.match) }?.price
    }

    public func cost(_ entry: UsageEntry) -> Double {
        guard let price = price(for: entry.model) else { return 0 }
        let perToken = 1.0 / 1_000_000
        return (Double(entry.input) * price.input + Double(entry.output) * price.output
            + Double(entry.cacheWrite) * price.cacheWrite + Double(entry.cacheRead) * price.cacheRead) * perToken
    }

    /// Tokens are summed per model first, so each model is priced once (not once per turn).
    public func cost(_ entries: [UsageEntry]) -> Double {
        var totals: [String: (input: Int, output: Int, cacheWrite: Int, cacheRead: Int)] = [:]
        for entry in entries {
            var t = totals[entry.model] ?? (0, 0, 0, 0)
            t.input += entry.input; t.output += entry.output
            t.cacheWrite += entry.cacheWrite; t.cacheRead += entry.cacheRead
            totals[entry.model] = t
        }
        return totals.reduce(0) { sum, item in
            sum + cost(UsageEntry(provider: .claude, date: .distantPast, model: item.key, input: item.value.input,
                                  output: item.value.output, cacheWrite: item.value.cacheWrite, cacheRead: item.value.cacheRead))
        }
    }
}

/// What the Usage tab shows for one provider.
public struct ProviderUsage: Equatable, Sendable {
    public struct Meter: Equatable, Sendable {
        public var label: String
        /// 0…1, nil when there is no limit to compare against.
        public var fraction: Double?
        public var tokens: Int?
        public var resetsAt: Date?
        /// True when the fraction is ZEUS's estimate rather than the provider's own number.
        public var estimated: Bool
    }

    public var provider: UsageProvider
    public var meters: [Meter]
    public var todayTokens: Int
    public var weekTokens: Int
    public var weekCost: Double
    /// Tokens per day for the last 7 days, oldest first.
    public var daily: [Int]
    public var topModel: String?
    public var lastActivity: Date?
    public var plan: String?

    public var hasData: Bool { lastActivity != nil || !meters.isEmpty }

    /// The meter closest to its limit; it drives the closed-notch ring and alerts.
    public var tightest: Meter? {
        meters.filter { $0.fraction != nil }.max { ($0.fraction ?? 0) < ($1.fraction ?? 0) }
    }
}

public enum UsageSummary {
    /// Builds the Usage card for one provider. For Claude, the 5-hour meter compares the
    /// current window with `blockLimit` (tokens), or with your busiest past window when no
    /// limit is set, so "100 %" means "as much as you have ever used in one window".
    public static func make(provider: UsageProvider, entries: [UsageEntry], codexLimits: CodexLimits? = nil,
                            blockLimit: Int? = nil, now: Date = Date(), calendar: Calendar = .current,
                            pricing: UsagePricing = .standard) -> ProviderUsage {
        // One pass, no copies: this runs every minute over ~100k entries.
        // Providers are appended one after another, each already in order; only check within this one.
        var previous = Date.distantPast, sorted = true
        for entry in entries where entry.provider == provider {
            if entry.date < previous { sorted = false; break }
            previous = entry.date
        }
        let source = sorted ? entries : entries.filter { $0.provider == provider }.sorted { $0.date < $1.date }
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let dayStarts = (0...7).map { calendar.date(byAdding: .day, value: $0, to: weekStart) ?? weekStart }
        var daily = [Int](repeating: 0, count: 7)
        var weekTokens = 0
        var byModel: [String: (input: Int, output: Int, cacheWrite: Int, cacheRead: Int, total: Int)] = [:]
        var lastDate: Date?
        var blockStart: Date?, blockEnd = Date.distantPast, blockTokens = 0, pastMax: Int?
        for entry in source where entry.provider == provider {
            lastDate = entry.date
            if provider == .claude {
                if blockStart != nil, entry.date < blockEnd {
                    blockTokens += entry.total
                } else {
                    if blockStart != nil { pastMax = max(pastMax ?? 0, blockTokens) }
                    let start = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                    blockStart = start; blockEnd = start.addingTimeInterval(UsageBlock.length); blockTokens = entry.total
                }
            }
            guard entry.date >= weekStart, entry.date <= now else { continue }
            weekTokens += entry.total
            if let day = (0..<7).last(where: { entry.date >= dayStarts[$0] }), entry.date < dayStarts[day + 1] {
                daily[day] += entry.total
            }
            var t = byModel[entry.model] ?? (0, 0, 0, 0, 0)
            t.input += entry.input; t.output += entry.output
            t.cacheWrite += entry.cacheWrite; t.cacheRead += entry.cacheRead; t.total += entry.total
            byModel[entry.model] = t
        }
        let weekCost = byModel.reduce(0.0) { sum, item in
            sum + pricing.cost(UsageEntry(provider: provider, date: .distantPast, model: item.key, input: item.value.input,
                                          output: item.value.output, cacheWrite: item.value.cacheWrite, cacheRead: item.value.cacheRead))
        }
        let activeBlock = blockStart.map { now >= $0 && now < blockEnd } ?? false
        if blockStart != nil, !activeBlock { pastMax = max(pastMax ?? 0, blockTokens) }

        var meters: [ProviderUsage.Meter] = []
        switch provider {
        case .codex:
            if let limits = codexLimits {
                meters = limits.windows.map { window in
                    // A reset that has already passed means the window started over.
                    let expired = window.resetsAt.map { $0 <= now } ?? false
                    return ProviderUsage.Meter(label: window.label, fraction: expired ? 0 : min(window.usedPercent / 100, 1),
                                               tokens: nil, resetsAt: expired ? nil : window.resetsAt, estimated: false)
                }
            }
        case .claude:
            let limit = blockLimit ?? pastMax
            let tokens = activeBlock ? blockTokens : 0
            meters.append(ProviderUsage.Meter(label: "5h", fraction: limit.map { $0 > 0 ? min(Double(tokens) / Double($0), 1) : 0 },
                                              tokens: tokens, resetsAt: activeBlock ? blockEnd : nil, estimated: true))
            meters.append(ProviderUsage.Meter(label: "Weekly", fraction: nil, tokens: weekTokens,
                                              resetsAt: nil, estimated: true))
        }

        return ProviderUsage(provider: provider, meters: meters,
                             todayTokens: daily.last ?? 0, weekTokens: weekTokens,
                             weekCost: weekCost, daily: daily,
                             topModel: byModel.max { $0.value.total < $1.value.total }?.key,
                             lastActivity: lastDate ?? (provider == .codex ? codexLimits?.date : nil),
                             plan: provider == .codex ? codexLimits?.plan : nil)
    }

    /// "1.2M", "34k", "980".
    public static func compact(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000_000...: String(format: "%.1fB", Double(tokens) / 1_000_000_000)
        case 1_000_000...: String(format: tokens >= 10_000_000 ? "%.0fM" : "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...: String(format: tokens >= 100_000 ? "%.0fk" : "%.1fk", Double(tokens) / 1_000)
        default: "\(tokens)"
        }
    }

    /// "2h 05m", "12m", "now".
    public static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 59 else { return "now" }
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return "\(minutes)m"
    }
}

/// Reads the logs from disk. Only files touched in the last `days` are opened, so a long
/// history stays cheap to scan.
public struct UsageScanner: Sendable {
    public var claudeRoots: [URL]
    public var codexRoot: URL
    public var days: Int

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, days: Int = 8) {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
        claudeRoots = [configDir ?? home.appendingPathComponent(".claude"), home.appendingPathComponent(".config/claude")]
            .map { $0.appendingPathComponent("projects", isDirectory: true) }
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
        codexRoot = (codexHome ?? home.appendingPathComponent(".codex")).appendingPathComponent("sessions", isDirectory: true)
        self.days = days
    }

    public struct Snapshot: Equatable, Sendable {
        public var entries: [UsageEntry]
        public var codexLimits: CodexLimits?
        /// True when no log grew since the previous scan, so callers can skip their rebuild.
        public var unchanged = false

        public init(entries: [UsageEntry] = [], codexLimits: CodexLimits? = nil) {
            self.entries = entries
            self.codexLimits = codexLimits
        }
    }

    /// Per-file read position and what was parsed so far. Logs only grow, so a refresh
    /// reads just the bytes appended since the last scan.
    final class Cache: @unchecked Sendable {
        struct File {
            var offset = 0
            var codex = CodexUsageParser.Result()
        }
        let lock = NSLock()
        var files: [URL: File] = [:]
        var last: Snapshot?
        var lastBuilt = Date.distantPast
        var lastLive: Set<URL> = []
        var claudeEntries: [UsageEntry] = []
        var seen: [Int: Date] = [:]
        var models: [String: String] = [:]
        func intern(_ model: String) -> String {
            if let known = models[model] { return known }
            let native = String(decoding: Array(model.utf8), as: UTF8.self)
            models[model] = native
            return native
        }
        var walks = (full: 0, targeted: 0)
    }

    /// How many full walks and targeted (watcher) scans ran; for tests and the perf budget.
    public var walkCounts: (full: Int, targeted: Int) {
        cache.lock.lock(); defer { cache.lock.unlock() }
        return cache.walks
    }

    let cache = Cache()

    /// Roots worth watching for changes (FSEvents in the app).
    public var watchRoots: [URL] { claudeRoots + [codexRoot] }

    /// - Parameter changed: nil walks every log folder (the first scan, then rarely). A set lists
    ///   the files a file watcher saw change; only those and the files already known are checked
    ///   with one stat each, so an idle minute walks nothing.
    public func scan(now: Date = Date(), changed: Set<URL>? = nil) -> Snapshot {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let claudeFiles: [(url: URL, size: Int)]
        let codexFiles: [(url: URL, size: Int)]
        if let changed, cache.last != nil {
            let known = Set(cache.files.keys).union(changed.filter { $0.pathExtension == "jsonl" })
            let stats = known.compactMap { url in Self.stat(url, since: cutoff).map { (url: url, size: $0) } }
            let codexPath = codexRoot.path + "/"
            claudeFiles = stats.filter { !$0.url.path.hasPrefix(codexPath) }
            codexFiles = stats.filter { $0.url.path.hasPrefix(codexPath) }
            cache.walks.targeted += 1
        } else {
            // Full pass: sizes come from the directory walk, so it opens only grown files.
            claudeFiles = claudeRoots.flatMap { Self.recentFiles(in: $0, since: cutoff) }
            codexFiles = Self.recentFiles(in: codexRoot, since: cutoff)
            cache.walks.full += 1
        }
        let liveNow = Set((claudeFiles + codexFiles).map(\.url))
        let grew = (claudeFiles + codexFiles).contains { $0.size != (cache.files[$0.url]?.offset ?? -1) }
        if !grew, liveNow == cache.lastLive, var last = cache.last, now.timeIntervalSince(cache.lastBuilt) < 3_600 {
            last.unchanged = true
            return last
        }
        // Claude turns are kept once, deduplicated across files by a 64-bit key hash, and only
        // new bytes are parsed: a refresh costs what the logs gained, not what they hold.
        if cache.claudeEntries.contains(where: { $0.date < cutoff }) {
            cache.claudeEntries.removeAll { $0.date < cutoff }
            cache.seen = cache.seen.filter { $0.value >= cutoff }
        }
        var live = Set<URL>()
        for (file, size) in claudeFiles {
            live.insert(file)
            var state = cache.files[file] ?? Cache.File()
            var reads = 0
            // Each chunk is read and parsed inside its own autorelease pool: FileHandle hands back
            // autoreleased buffers, and a detached task never drains on its own (peak was 3.3 GB).
            while size != state.offset, reads < 64 {
                let consumed: Int? = autoreleasepool { () -> Int? in
                guard let (data, start) = Self.read(file, from: &state.offset, limit: Self.chunk) else { return nil }
                reads += 1
                let result = ClaudeUsageParser.scan(data)
                for item in result.items where item.entry.date >= cutoff {
                    let key = item.key.hashValue
                    guard cache.seen[key] == nil else { continue }
                    cache.seen[key] = item.entry.date
                    var entry = item.entry
                    entry.model = cache.intern(entry.model)
                    cache.claudeEntries.append(entry)
                }
                // A chunk that ends mid-line with no newline at all would stall; skip past it.
                state.offset = start + (result.consumed > 0 || data.count < Self.chunk ? result.consumed : data.count)
                return result.consumed
                }
                guard let consumed, consumed > 0 else { break }
            }
            cache.files[file] = state
        }
        // Kept in time order, so summaries skip their sort; new turns mostly land at the end.
        if !cache.claudeEntries.isSorted(by: \.date) { cache.claudeEntries.sort { $0.date < $1.date } }
        var entries = cache.claudeEntries
        var limits: CodexLimits?
        var codexEntries: [UsageEntry] = []
        for (file, size) in codexFiles {
            live.insert(file)
            var state = cache.files[file] ?? Cache.File()
            if size != state.offset {
                autoreleasepool {
                    guard let (data, start) = Self.read(file, from: &state.offset) else { return }
                    if start == 0 { state.codex = CodexUsageParser.Result() }
                    state.offset = start + CodexUsageParser.parse(data, into: &state.codex)
                }
            }
            cache.files[file] = state
            codexEntries += state.codex.entries.filter { $0.date >= cutoff }
            if let snapshot = state.codex.limits, snapshot.date > (limits?.date ?? .distantPast) { limits = snapshot }
        }
        cache.files = cache.files.filter { live.contains($0.key) }
        if !codexEntries.isSorted(by: \.date) { codexEntries.sort { $0.date < $1.date } }
        entries += codexEntries
        let snapshot = Snapshot(entries: entries, codexLimits: limits)
        cache.last = snapshot
        cache.lastBuilt = now
        cache.lastLive = live
        return snapshot
    }

    /// New bytes since `offset`, or nil when nothing changed. A file that shrank was
    /// rewritten, so it is read again from the start (offset reset to 0).
    /// Largest slice read at once, so a 100 MB transcript never sits in memory whole.
    static let chunk = 8 << 20

    public static func read(_ url: URL, from offset: inout Int, limit: Int = .max) -> (Data, Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        if Int(size) < offset { offset = 0 }
        guard Int(size) > offset else { return nil }
        try? handle.seek(toOffset: UInt64(offset))
        let count = min(Int(size) - offset, limit)
        guard let data = try? handle.read(upToCount: count) else { return nil }
        return (data, offset)
    }

    /// Size of one log if it changed since `cutoff`, else nil (gone or too old).
    static func stat(_ url: URL, since cutoff: Date) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              (values.contentModificationDate ?? .distantPast) >= cutoff else { return nil }
        return values.fileSize ?? -1
    }

    static func recentFiles(in root: URL, since cutoff: Date) -> [(url: URL, size: Int)] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var files: [(url: URL, size: Int)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if (values?.contentModificationDate ?? .distantPast) >= cutoff { files.append((url, values?.fileSize ?? -1)) }
        }
        return files
    }
}
