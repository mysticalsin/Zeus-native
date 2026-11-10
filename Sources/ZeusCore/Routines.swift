import Foundation

/// When a routine runs: every day or on weekdays, at a time of day.
public struct RoutineSchedule: Codable, Equatable, Hashable, Sendable {
    public enum Days: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily, weekdays
        public var id: String { rawValue }
        public var title: String { self == .daily ? "Every day" : "Weekdays" }
    }

    public var days: Days
    public var hour: Int
    public var minute: Int

    public init(days: Days = .weekdays, hour: Int = 9, minute: Int = 0) {
        self.days = days
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    func runsOn(_ date: Date, calendar: Calendar) -> Bool {
        days == .daily || !calendar.isDateInWeekend(date)
    }

    func time(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// The first run strictly after `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            if runsOn(day, calendar: calendar), let time = time(on: day, calendar: calendar), time > date { return time }
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = following
        }
        return nil
    }

    /// The latest scheduled run at or before `date`.
    public func previous(atOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            if runsOn(day, calendar: calendar), let time = time(on: day, calendar: calendar), time <= date { return time }
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            day = earlier
        }
        return nil
    }

    /// A run that was due since `lastRun` (or since `created` for a routine that never ran)
    /// and hasn't happened: the Mac was asleep or off. Only the latest one counts, so a week
    /// away catches up once, not seven times.
    public func missed(lastRun: Date?, created: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard let due = previous(atOrBefore: now, calendar: calendar) else { return nil }
        let since = lastRun ?? created
        return due > since ? due : nil
    }

    /// "Weekdays at 09:00".
    public var summary: String { String(format: "%@ at %02d:%02d", days.title, hour, minute) }
}

/// A saved prompt that runs on a schedule through the model router.
public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var schedule: RoutineSchedule
    public var engine: RouterChoice
    public var enabled: Bool
    public var created: Date
    public var lastRun: Date?

    /// Voice-created routines default to local Ollama (no plan quota).
    public static let voiceDefaultEngine: RouterChoice = .engine(.ollama)

    public init(id: UUID = UUID(), name: String, prompt: String, schedule: RoutineSchedule = RoutineSchedule(),
                engine: RouterChoice = .auto, enabled: Bool = true, created: Date = Date(), lastRun: Date? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.engine = engine
        self.enabled = enabled
        self.created = created
        self.lastRun = lastRun
    }

    public func isDue(now: Date, calendar: Calendar = .current) -> Bool {
        enabled && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && schedule.missed(lastRun: lastRun, created: created, now: now, calendar: calendar) != nil
    }
}

/// One finished run, kept in history.
public struct RoutineRun: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var routineID: UUID
    public var routineName: String
    public var date: Date
    public var engine: String?
    public var output: String
    public var failed: Bool

    public init(id: UUID = UUID(), routineID: UUID, routineName: String, date: Date, engine: String?, output: String, failed: Bool) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.date = date
        self.engine = engine
        self.output = output
        self.failed = failed
    }
}

public enum RoutinePlanner {
    /// When the scheduler should next wake up: the earliest upcoming run of an enabled routine.
    public static func nextWake(_ routines: [Routine], now: Date, calendar: Calendar = .current) -> Date? {
        routines.filter(\.enabled).compactMap { $0.schedule.next(after: now, calendar: calendar) }.min()
    }

    public static func due(_ routines: [Routine], now: Date, calendar: Calendar = .current) -> [Routine] {
        routines.filter { $0.isDue(now: now, calendar: calendar) }
    }
}

/// Routines and their last 50 runs, as JSON in Application Support.
public struct RoutineStore: Sendable {
    public struct Contents: Codable, Equatable, Sendable {
        public var routines: [Routine] = []
        public var runs: [RoutineRun] = []
        public init(routines: [Routine] = [], runs: [RoutineRun] = []) {
            self.routines = routines
            self.runs = runs
        }
    }

    public static let historyLimit = 50
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: RoutineStore {
        RoutineStore(url: ZeusPaths.supportDirectory.appendingPathComponent("routines.json"))
    }

    public func load() -> Contents {
        guard let data = try? Data(contentsOf: url) else { return Contents() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Contents.self, from: data)) ?? Contents()
    }

    /// Like `load`, but says when the file is there and could not be read, so the caller can set
    /// it aside instead of letting the next save replace it with an empty set.
    public func loadChecked() -> (contents: Contents, unreadable: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (Contents(), false) }
        guard let data = try? Data(contentsOf: url) else { return (Contents(), true) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data) else { return (Contents(), true) }
        return (contents, false)
    }

    /// Moves an unreadable file to `routines.json.bad-<stamp>` and returns where it went.
    @discardableResult
    public func setAsideUnreadable(now: Date = Date()) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        var target = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bad-\(stamp)")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bad-\(stamp)-\(counter)")
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    public func save(_ contents: Contents) throws {
        var trimmed = contents
        trimmed.runs = Array(contents.runs.sorted { $0.date > $1.date }.prefix(Self.historyLimit))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(trimmed).write(to: url, options: .atomic)
    }
}
