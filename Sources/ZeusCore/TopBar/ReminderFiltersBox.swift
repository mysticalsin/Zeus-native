import Foundation

/// Chip membership, one-tap due times, and the clock at the end of a reminder draft.
/// Today is due before the next midnight, including a due that is already past. A due at that midnight is tomorrow.
/// This evening is 18:00, and it moves to tomorrow once 18:00 has arrived. Next week is the coming Monday at 9:00,
/// or seven days on when today is Monday. An hour ahead lands on the next quarter hour, and an exact quarter stays.
/// The box takes the filter, the due date, the flag, the text, the date, and the calendar.
/// It does not read a screen, a pointer, a clock, or a stored setting. `day` reads the words left after the clock.
public enum ReminderFiltersBox {
    public struct Draft: Equatable, Sendable {
        public var title: String
        public var due: Date?
        public var hasTime: Bool
    }

    public static func includes(
        _ filter: ReminderFilter, due: Date?, flagged: Bool, now: Date, calendar: Calendar
    ) -> Bool {
        switch filter {
        case .all: return true
        case .flagged: return flagged
        case .scheduled: return due != nil
        case .today:
            guard let due else { return false }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
            return due < tomorrow
        }
    }

    public static func quickDue(_ kind: ReminderQuickDue, now: Date, calendar: Calendar) -> Date {
        func at(_ day: Date, hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day }
        switch kind {
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
            // The coming Monday at 9:00. A Monday waits seven days.
            let weekday = calendar.component(.weekday, from: now)
            let ahead = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
            return at(calendar.date(byAdding: .day, value: ahead, to: now) ?? now, hour: 9)
        }
    }

    /// `day` reads the words left after the clock. The box does not choose the day.
    public static func draft(
        _ text: String,
        now: Date,
        calendar: Calendar,
        day: (String) -> (title: String, due: Date?)
    ) -> Draft {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var time: (hour: Int, minute: Int)?
        if let (parsed, take) = trailingTime(words) {
            time = parsed
            words.removeLast(take)
            if words.last?.lowercased() == "at" { words.removeLast() }
        }
        let reading = day(words.joined(separator: " "))
        var due = reading.due
        if let time {
            // A time with no day is today, or tomorrow when it has already passed.
            var base = due ?? now
            if due == nil, let candidate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now), candidate <= now {
                base = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            }
            due = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
        }
        return Draft(title: reading.title, due: due, hasTime: time != nil)
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
