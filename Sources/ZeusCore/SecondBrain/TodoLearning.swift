import Foundation

/// On-device learning for the To-do tab: remembers recurring titles, usual due offsets,
/// push-backs, and wording. Suggests due times, splits big tasks, ranks what to do next,
/// and explains why. Never leaves this Mac.
public struct TodoLearning: Codable, Equatable, Sendable {
    public struct Pattern: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        /// Normalised title key (folded, lowercased).
        public var key: String
        public var sampleTitle: String
        public var timesSeen: Int
        public var timesDone: Int
        public var timesPushed: Int
        /// Typical days from creation to due (when a due was set).
        public var dueOffsets: [Int]
        /// Hour-of-day buckets when the task was usually added (0…23).
        public var addHours: [Int]
        public var lastSeen: Date

        public init(id: String = UUID().uuidString, key: String, sampleTitle: String, timesSeen: Int = 1,
                    timesDone: Int = 0, timesPushed: Int = 0, dueOffsets: [Int] = [], addHours: [Int] = [],
                    lastSeen: Date = Date()) {
            self.id = id
            self.key = key
            self.sampleTitle = sampleTitle
            self.timesSeen = timesSeen
            self.timesDone = timesDone
            self.timesPushed = timesPushed
            self.dueOffsets = dueOffsets
            self.addHours = addHours
            self.lastSeen = lastSeen
        }
    }

    public struct Suggestion: Equatable, Sendable, Identifiable {
        public var id: String { kind + ":" + title }
        public var kind: String
        public var title: String
        public var due: String?
        public var reason: String
        public var split: [String]
    }

    public var patterns: [Pattern]
    public var enabled: Bool

    public init(patterns: [Pattern] = [], enabled: Bool = true) {
        self.patterns = patterns
        self.enabled = enabled
    }

    public static func key(for title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func observeAdd(_ title: String, due: String?, now: Date = Date(), calendar: Calendar = .current) {
        guard enabled else { return }
        let k = Self.key(for: title)
        guard !k.isEmpty else { return }
        let hour = calendar.component(.hour, from: now)
        if let index = patterns.firstIndex(where: { $0.key == k }) {
            patterns[index].timesSeen += 1
            patterns[index].sampleTitle = title
            patterns[index].addHours.append(hour)
            if patterns[index].addHours.count > 24 { patterns[index].addHours.removeFirst() }
            if let due, let day = dayDiff(from: now, due: due, calendar: calendar), abs(day) <= 366 * 2 {
                patterns[index].dueOffsets.append(day)
                if patterns[index].dueOffsets.count > 12 { patterns[index].dueOffsets.removeFirst() }
            }
            patterns[index].lastSeen = now
        } else {
            var dueOffsets: [Int] = []
            if let due, let day = dayDiff(from: now, due: due, calendar: calendar), abs(day) <= 366 * 2 { dueOffsets = [day] }
            patterns.append(Pattern(key: k, sampleTitle: title, dueOffsets: dueOffsets, addHours: [hour], lastSeen: now))
        }
        if patterns.count > 200 {
            patterns.sort { $0.lastSeen > $1.lastSeen }
            patterns = Array(patterns.prefix(200))
        }
    }

    public mutating func observeDone(_ title: String) {
        guard enabled else { return }
        let k = Self.key(for: title)
        guard let index = patterns.firstIndex(where: { $0.key == k }) else { return }
        patterns[index].timesDone += 1
        patterns[index].lastSeen = Date()
    }

    public mutating func observePushBack(_ title: String, from: String?, to: String?, calendar: Calendar = .current) {
        guard enabled else { return }
        let k = Self.key(for: title)
        guard let index = patterns.firstIndex(where: { $0.key == k }) else { return }
        patterns[index].timesPushed += 1
        if let from, let to, let a = TodoQuickAdd.day(from), let b = TodoQuickAdd.day(to) {
            let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
            if days > 0 {
                patterns[index].dueOffsets.append(days)
                if patterns[index].dueOffsets.count > 12 { patterns[index].dueOffsets.removeFirst() }
            }
        }
        patterns[index].lastSeen = Date()
    }

    public mutating func clear() { patterns = [] }

    /// Suggest a due day for a fresh title from past patterns (same wording or close).
    public func suggestDue(for title: String, now: Date = Date(), calendar: Calendar = .current) -> Suggestion? {
        guard enabled else { return nil }
        let k = Self.key(for: title)
        // Exact title only. "buy" must not lend its due day to "buy milk".
        guard let pattern = patterns.first(where: { $0.key == k }),
              pattern.timesSeen >= 2 else { return nil }
        // Offsets past two years are the poisoned Persian-year loop (about -226888, then -453781), not a habit.
        let offsets = pattern.dueOffsets.filter { abs($0) <= 366 * 2 }
        guard !offsets.isEmpty else { return nil }
        let offset = median(offsets)
        let dueDate = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        let due = TodoQuickAdd.dayString(dueDate, calendar: calendar)
        guard TodoQuickAdd.yearIsNear(due, now: now, timeZone: calendar.timeZone) else { return nil }
        return Suggestion(kind: "due", title: title, due: due,
                          reason: "You usually give “\(pattern.sampleTitle)” about \(offset) day\(offset == 1 ? "" : "s").",
                          split: [])
    }

    /// Recurring titles that are not currently open — bring them back.
    public func recurringSuggestions(openTitles: [String], now: Date = Date(), calendar: Calendar = .current) -> [Suggestion] {
        guard enabled else { return [] }
        let open = Set(openTitles.map(Self.key(for:)))
        return patterns
            .filter { $0.timesDone >= 2 && $0.timesSeen >= 3 && !open.contains($0.key) }
            .sorted { $0.timesDone > $1.timesDone }
            .prefix(5)
            .map { pattern in
                let due = suggestDue(for: pattern.sampleTitle, now: now, calendar: calendar)?.due
                return Suggestion(kind: "recurring", title: pattern.sampleTitle, due: due,
                                  reason: "You finished this \(pattern.timesDone) times. Bring it back?",
                                  split: [])
            }
    }

    /// Split a long title that looks like several tasks joined with "and"/commas.
    public func suggestSplit(_ title: String) -> Suggestion? {
        guard enabled else { return nil }
        let parts = TodoVoice.split(title).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count >= 2, title.count >= 28 else { return nil }
        return Suggestion(kind: "split", title: title, due: nil,
                          reason: "Looks like \(parts.count) tasks. Split them?",
                          split: parts)
    }

    /// Rank open items: overdue first, then learned usual hour, then due soon, then older.
    public func rank(_ items: [TodoItem], now: Date = Date(), calendar: Calendar = .current) -> [TodoItem] {
        let today = TodoQuickAdd.dayString(now, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        return items.sorted { a, b in
            score(a, today: today, hour: hour) > score(b, today: today, hour: hour)
        }
    }

    public func rankReason(for item: TodoItem, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard enabled else { return nil }
        let today = TodoQuickAdd.dayString(now, calendar: calendar)
        if let due = item.due, due < today { return "Overdue — do this next." }
        if let due = item.due, due == today { return "Due today." }
        let k = Self.key(for: item.title)
        if let pattern = patterns.first(where: { $0.key == k }), let usual = mode(pattern.addHours),
           abs(usual - calendar.component(.hour, from: now)) <= 1 {
            return "You usually handle “\(pattern.sampleTitle)” around now."
        }
        if let pattern = patterns.first(where: { $0.key == k }), pattern.timesPushed >= 2 {
            return "You’ve pushed this back before — finish it this time."
        }
        return nil
    }

    private func score(_ item: TodoItem, today: String, hour: Int) -> Int {
        var value = 0
        if let due = item.due {
            if due < today { value += 100 }
            else if due == today { value += 60 }
            else { value += 20 }
        }
        let k = Self.key(for: item.title)
        if let pattern = patterns.first(where: { $0.key == k }) {
            value += min(pattern.timesDone, 10) * 2
            if let usual = mode(pattern.addHours), abs(usual - hour) <= 1 { value += 25 }
            if pattern.timesPushed >= 2 { value += 15 }
        }
        return value
    }

    private func dayDiff(from now: Date, due: String, calendar: Calendar) -> Int? {
        guard let day = TodoQuickAdd.day(due) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day
    }

    private func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func mode(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let counted = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return counted.max(by: { $0.value < $1.value })?.key
    }
}

/// Disk-backed store for `TodoLearning`.
public struct TodoLearningStore: Sendable {
    public var file: URL
    public var learning: TodoLearning

    public init(file: URL, learning: TodoLearning = TodoLearning()) {
        self.file = file
        self.learning = learning
    }

    public static func load(file: URL) -> TodoLearningStore {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(TodoLearning.self, from: data) {
            return TodoLearningStore(file: file, learning: decoded)
        }
        return TodoLearningStore(file: file)
    }

    public mutating func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(learning) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
