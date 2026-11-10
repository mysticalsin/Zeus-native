import Foundation

/// A calendar event as the morning brief needs it.
public struct BriefEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var hasCall: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, hasCall: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.hasCall = hasCall
    }
}

/// A to-do with a due date, from Reminders or ZEUS's own list.
public struct BriefTodo: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?
    /// Due on a day, without a time.
    public var dateOnly: Bool
    public var done: Bool

    public init(id: String, title: String, due: Date?, dateOnly: Bool = false, done: Bool = false) {
        self.id = id
        self.title = title
        self.due = due
        self.dateOnly = dateOnly
        self.done = done
    }
}

/// The morning brief card: a greeting, the day's shape, and what is due.
public struct MorningBrief: Equatable, Sendable {
    public var greeting: String
    public var summary: String
    public var events: [BriefEvent]
    public var dueToday: [BriefTodo]
    public var overdue: Int

    public static func build(now: Date, events: [BriefEvent], todos: [BriefTodo], name: String?,
                             calendar: Calendar = .current) -> MorningBrief {
        let hour = calendar.component(.hour, from: now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let greeting = trimmed.isEmpty ? part : "\(part), \(trimmed.split(separator: " ").first.map(String.init) ?? trimmed)"

        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let today = events.filter { $0.end > now && $0.start < dayEnd }.sorted { $0.start < $1.start }
        let open = todos.filter { !$0.done && $0.due != nil }
        let dueToday = open.filter { ($0.due ?? .distantFuture) >= dayStart && ($0.due ?? .distantFuture) < dayEnd }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        let overdue = open.filter { ($0.due ?? .distantFuture) < dayStart }.count

        var parts: [String] = []
        let timed = today.filter { !$0.isAllDay }
        if timed.isEmpty {
            parts.append("No meetings today")
        } else {
            let calls = timed.filter(\.hasCall).count
            parts.append("\(timed.count) \(timed.count == 1 ? "event" : "events")" + (calls > 0 ? ", \(calls) with a call" : ""))
            if let first = timed.first, first.start > now {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "HH:mm"
                parts.append("first at \(formatter.string(from: first.start))")
            }
        }
        if !dueToday.isEmpty { parts.append("\(dueToday.count) due today") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        return MorningBrief(greeting: greeting, summary: parts.joined(separator: " · "), events: Array(today.prefix(4)),
                            dueToday: Array(dueToday.prefix(4)), overdue: overdue)
    }
}

/// Shows the brief once a day, at the first unlock between `from` and `until` o'clock.
public struct FirstUnlockGate: Equatable, Sendable {
    public var from = 5
    public var until = 14
    public private(set) var lastShownDay: String?

    public init(lastShownDay: String? = nil) {
        self.lastShownDay = lastShownDay
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func shouldShow(at now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= from && hour < until && lastShownDay != Self.dayKey(now, calendar: calendar)
    }

    public mutating func markShown(at now: Date, calendar: Calendar = .current) {
        lastShownDay = Self.dayKey(now, calendar: calendar)
    }
}

/// Whether ZEUS may put a card on screen right now.
public enum ProactiveQuiet {
    public static func allowsCard(fullScreen: Bool, focusActive: Bool) -> Bool {
        !fullScreen && !focusActive
    }
}

/// System notifications for due to-dos, scheduled ahead so no timer runs. macOS holds them
/// back during Focus on its own.
public struct DueNudge: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fireDate: Date

    public static let prefix = "zeus.todo."

    /// Nudges for open to-dos due in the next `horizon`. Date-only items fire at `morningHour`.
    public static func plan(_ todos: [BriefTodo], now: Date, horizon: TimeInterval = 48 * 3600, morningHour: Int = 9,
                            calendar: Calendar = .current) -> [DueNudge] {
        todos.compactMap { todo -> DueNudge? in
            guard !todo.done, let due = todo.due else { return nil }
            let fire: Date
            if todo.dateOnly {
                fire = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: due) ?? due
            } else {
                fire = due
            }
            guard fire > now, fire.timeIntervalSince(now) <= horizon else { return nil }
            let stamp = Int(fire.timeIntervalSince1970)
            return DueNudge(id: "\(prefix)\(todo.id).\(stamp)", title: todo.title,
                            body: todo.dateOnly ? "Due today" : "Due now", fireDate: fire)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    /// What to add and remove so the scheduled set matches the plan.
    public static func diff(planned: [DueNudge], scheduled: Set<String>) -> (add: [DueNudge], remove: [String]) {
        let plannedIDs = Set(planned.map(\.id))
        let add = planned.filter { !scheduled.contains($0.id) }
        let remove = scheduled.filter { $0.hasPrefix(prefix) && !plannedIDs.contains($0) }.sorted()
        return (add, remove)
    }
}
