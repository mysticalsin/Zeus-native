import Foundation

/// The chips on the Reminders page.
public enum ReminderFilter: String, CaseIterable, Identifiable, Sendable {
    case today = "Today", scheduled = "Scheduled", all = "All", flagged = "Flagged"
    public var id: String { rawValue }

    /// Today: due today or already overdue. Scheduled: has a due date. All. Flagged: marked important
    /// (EventKit does not expose Reminders' flag, so ZEUS reads high priority as flagged).
    public func includes(due: Date?, flagged: Bool, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        switch self {
        case .all: return true
        case .flagged: return flagged
        case .scheduled: return due != nil
        case .today:
            guard let due else { return false }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
            return due < tomorrow
        }
    }
}

/// One-tap due times for a new reminder.
public enum ReminderQuickDue: String, CaseIterable, Identifiable, Sendable {
    case inAnHour = "In 1 hour", thisEvening = "This evening", tomorrowMorning = "Tomorrow 9:00", nextWeek = "Next week"
    public var id: String { rawValue }

    public func date(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        func at(_ day: Date, hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day }
        switch self {
        case .inAnHour:
            // On the next quarter hour, at least an hour away.
            let target = now.addingTimeInterval(3600)
            let minute = calendar.component(.minute, from: target)
            return calendar.date(byAdding: .minute, value: (15 - minute % 15) % 15, to: calendar.date(bySetting: .second, value: 0, of: target) ?? target) ?? target
        case .thisEvening:
            let evening = at(now, hour: 18)
            return evening > now ? evening : at(calendar.date(byAdding: .day, value: 1, to: now) ?? now, hour: 18)
        case .tomorrowMorning:
            return at(calendar.date(byAdding: .day, value: 1, to: now) ?? now, hour: 9)
        case .nextWeek:
            // The coming Monday at 9:00.
            let weekday = calendar.component(.weekday, from: now)
            let ahead = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
            return at(calendar.date(byAdding: .day, value: ahead, to: now) ?? now, hour: 9)
        }
    }
}

/// "pay rent friday at 5pm", "call Ana tomorrow 9:30", "water plants at 18:00": a title, a day and a time.
public enum ReminderDraft {
    public struct Parsed: Equatable, Sendable {
        public var title: String
        public var due: Date?
        public var hasTime: Bool
    }

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Parsed {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var time: (hour: Int, minute: Int)?
        if let (parsed, take) = trailingTime(words) {
            time = parsed
            words.removeLast(take)
            if words.last?.lowercased() == "at" { words.removeLast() }
        }
        let day = TodoQuickAdd.parse(words.joined(separator: " "), now: now, calendar: calendar)
        var due = day.due.flatMap { TodoQuickAdd.day($0, calendar: calendar) }
        if let time {
            // A time with no day is today, or tomorrow when it has already passed.
            var base = due ?? now
            if due == nil, let candidate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now), candidate <= now {
                base = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            }
            due = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
        }
        return Parsed(title: day.title, due: due, hasTime: time != nil)
    }

    /// The time at the end of the words, and how many words it took ("5pm" is one, "5 pm" and "at 17:30" count their parts).
    static func trailingTime(_ words: [String]) -> ((hour: Int, minute: Int), Int)? {
        guard let last = words.last?.lowercased() else { return nil }
        let afterAt = words.count >= 2 && words[words.count - 2].lowercased() == "at"
        // "5 pm"
        if (last == "am" || last == "pm"), words.count >= 2, let parsed = clock(words[words.count - 2].lowercased() + last, requireMarker: false) {
            return (parsed, 2)
        }
        if let parsed = clock(last, requireMarker: !afterAt) { return (parsed, 1) }
        return nil
    }

    /// "5pm", "5:30pm", "17:30", "9". A bare number needs `requireMarker` off ("at 9").
    static func clock(_ word: String, requireMarker: Bool) -> (hour: Int, minute: Int)? {
        var text = word
        var meridiem: String?
        if text.hasSuffix("am") || text.hasSuffix("pm") { meridiem = String(text.suffix(2)); text = String(text.dropLast(2)) }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let hour = Int(parts[0]), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) ?? -1 : 0
        if requireMarker, meridiem == nil, parts.count == 1 { return nil }
        guard (0...59).contains(minute) else { return nil }
        var h = hour
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            h = hour % 12 + (meridiem == "pm" ? 12 : 0)
        }
        guard (0...23).contains(h) else { return nil }
        return (h, minute)
    }
}
