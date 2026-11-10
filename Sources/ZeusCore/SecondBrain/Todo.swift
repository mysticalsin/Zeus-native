import Foundation

/// One to-do. In a connected note it is a Markdown task line: `- [ ] Call Anna 📅 2026-11-02`.
public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var done: Bool
    /// A calendar day (yyyy-MM-dd), kept as text so time zones never shift it.
    public var due: String?

    public init(id: UUID = UUID(), title: String, done: Bool = false, due: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.due = due
    }
}

/// The to-do list and its edits, independent of where it is stored.
public struct TodoList: Codable, Equatable, Sendable {
    public var items: [TodoItem]

    public init(items: [TodoItem] = []) { self.items = items }

    public var open: [TodoItem] { items.filter { !$0.done } }

    @discardableResult
    public mutating func add(_ title: String, due: String? = nil) -> TodoItem? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let item = TodoItem(title: clean, due: due)
        items.append(item)
        return item
    }

    public mutating func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }

    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    public mutating func setDue(_ id: UUID, _ due: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].due = due
    }

    public mutating func rename(_ id: UUID, _ title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = clean
    }

    /// Moves an item up (negative) or down (positive), clamped to the list.
    public mutating func move(_ id: UUID, by delta: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + delta, 0), items.count - 1)
        guard to != from else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
    }

    /// Takes a freshly read list (from a note) but keeps the ids of items it already had,
    /// matched by title, so the UI doesn't flicker and in-flight edits find their item.
    public mutating func adopt(_ parsed: [TodoItem]) {
        var pool = items
        items = parsed.map { incoming in
            if let index = pool.firstIndex(where: { $0.title == incoming.title }) {
                var kept = pool.remove(at: index)
                kept.done = incoming.done
                kept.due = incoming.due
                return kept
            }
            return incoming
        }
    }
}

/// Reads and writes Markdown task lines (Obsidian, Logseq, plain Markdown).
/// Writing only ever touches task lines: headings, notes and everything else stay as they were.
public enum TodoMarkdown {
    public static let dueMarker = "📅"

    public struct Line: Equatable, Sendable {
        public var indent: String
        public var bullet: Character
        public var done: Bool
        public var title: String
        public var due: String?
    }

    public static func parse(line: String) -> Line? {
        var rest = Substring(line)
        let indent = String(rest.prefix { $0 == " " || $0 == "\t" })
        rest = rest.dropFirst(indent.count)
        guard let bullet = rest.first, bullet == "-" || bullet == "*" || bullet == "+" else { return nil }
        rest = rest.dropFirst()
        guard rest.hasPrefix(" [") else { return nil }
        rest = rest.dropFirst(2)
        guard let mark = rest.first, mark == " " || mark == "x" || mark == "X" else { return nil }
        rest = rest.dropFirst()
        guard rest.hasPrefix("]") else { return nil }
        rest = rest.dropFirst()
        var title = rest.trimmingCharacters(in: .whitespaces)
        var due: String?
        if let range = title.range(of: dueMarker) {
            let after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let date = String(after.prefix(10))
            if isDay(date) {
                due = date
                title = (String(title[..<range.lowerBound]) + after.dropFirst(10)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !title.isEmpty else { return nil }
        return Line(indent: indent, bullet: bullet, done: mark != " ", title: title, due: due)
    }

    public static func render(_ item: TodoItem, indent: String = "", bullet: Character = "-") -> String {
        var text = "\(indent)\(bullet) [\(item.done ? "x" : " ")] \(item.title)"
        if let due = item.due { text += " \(dueMarker) \(due)" }
        return text
    }

    /// Top-level tasks in a note, in order (nested sub-tasks are left to the note).
    public static func items(in text: String) -> [TodoItem] {
        text.components(separatedBy: "\n").compactMap { parse(line: $0) }.filter { $0.indent.isEmpty }
            .map { TodoItem(title: $0.title, done: $0.done, due: $0.due) }
    }

    /// Writes `items` back into `text`: the existing top-level task lines are the slots, filled
    /// in the new order; extra items go after the last task (or at the end); leftover slots go away.
    public static func apply(_ items: [TodoItem], to text: String, heading: String = "## To-do") -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let slots = lines.indices.filter { index in
            guard let parsed = parse(line: lines[index]) else { return false }
            return parsed.indent.isEmpty
        }
        let bullet = slots.first.flatMap { parse(line: lines[$0])?.bullet } ?? "-"
        for (slot, item) in zip(slots, items) { lines[slot] = render(item, bullet: bullet) }
        if items.count > slots.count {
            let extra = items[slots.count...].map { render($0, bullet: bullet) }
            if let last = slots.last {
                lines.insert(contentsOf: extra, at: last + 1)
            } else {
                while lines.last?.isEmpty == true { lines.removeLast() }
                if !lines.isEmpty { lines.append("") }
                lines.append(heading)
                lines.append(contentsOf: extra)
            }
        } else if slots.count > items.count {
            for index in slots[items.count...].reversed() { lines.remove(at: index) }
        }
        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        return text.count == 10 && parts.count == 3 && parts[0].count == 4 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

/// "call Anna tomorrow", "pay rent by friday", "ship it due 2026-11-03": the title and a due day.
public enum TodoQuickAdd {
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> (title: String, due: String?) {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let greg = storedCalendar(calendar)
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var due: Date?
        func lower(_ index: Int) -> String { words[index].lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let lead: Set<String> = ["due", "by", "on", "for"]

        // "due 2026-11-03" or a trailing ISO date. A bare number in the title ("buy 2 milk") is not a date.
        if let index = words.firstIndex(where: { TodoMarkdown.isDay($0) }) {
            due = day(words[index], calendar: greg)
            words.remove(at: index)
            if index > 0, lead.contains(lower(index - 1)) { words.remove(at: index - 1) }
        } else if let last = words.indices.last {
            let word = lower(last)
            var take = 1
            var date: Date?
            if word == "today" || word == "tonight" { date = now }
            else if word == "tomorrow" { date = greg.date(byAdding: .day, value: 1, to: now) }
            else if word == "week", last > 0, lower(last - 1) == "next" {
                date = greg.date(byAdding: .day, value: 7, to: now); take = 2
            } else if word.rangeOfCharacter(from: .decimalDigits) == nil,
                      let weekday = weekdays.firstIndex(where: { $0 == word || (word.count >= 3 && $0.prefix(3) == word) }) {
                let today = greg.component(.weekday, from: now) - 1
                var ahead = (weekday - today + 7) % 7
                if ahead == 0 { ahead = 7 }
                date = greg.date(byAdding: .day, value: ahead, to: now)
            }
            if let date {
                due = date
                words.removeLast(take)
                if let end = words.indices.last, lead.contains(lower(end)) { words.removeLast() }
            }
        }
        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let due else { return (title, nil) }
        let stored = dayString(due, calendar: greg)
        // QA20: "buy milk" was saved as 0784-06-02. A stored day is always Gregorian, and a year
        // far from now is not a due date (the words stay in the title).
        guard yearIsNear(stored, now: now, timeZone: greg.timeZone) else { return (original, nil) }
        return (title, stored)
    }

    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// True when `day` (yyyy-MM-dd) is within 20 years of `now`. 0784 and a Persian year like 1405 are not.
    public static func yearIsNear(_ day: String, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard day.count >= 4, let year = Int(day.prefix(4)) else { return false }
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = timeZone
        return abs(year - greg.component(.year, from: now)) <= 20
    }

    /// The stored due day is always Gregorian, in `calendar`'s time zone.
    /// `Calendar.current` on this Mac is Persian: formatting with it writes year 1405, and the next
    /// read treats 1405 as a Gregorian year, which walks the due date back to year 0784.
    public static func dayString(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = storedCalendar(calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func day(_ text: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return storedCalendar(calendar).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Gregorian calendar that keeps the caller's time zone, so "tomorrow" and "Friday" follow the wall clock.
    static func storedCalendar(_ calendar: Calendar) -> Calendar {
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = calendar.timeZone
        greg.locale = Locale(identifier: "en_US_POSIX")
        return greg
    }
}
