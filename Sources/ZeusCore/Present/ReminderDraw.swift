import Foundation

/// An Apple reminder just added, drawn while Zeus says so.
///
/// The voice says the full line. The screen builds Reminder, then the title, then the
/// due line when there is one. A to-do stays on its own card.
public enum ReminderAsk {
    public static let access = "I need Reminders access to add that."
    public static let notSaved = "The reminder wasn't saved."

    /// The reminder text after "new reminder" or "add an apple reminder". A to-do phrase is not this.
    public static func body(in text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        let folded = cleaned.lowercased()
        let heads = ["add an apple reminder", "add apple reminder", "new reminder", "apple reminder"]
        for head in heads {
            guard let range = folded.range(of: head) else { continue }
            let prefix = folded[..<range.lowerBound]
            let prefixWords = prefix.split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty }
            let filler: Set<String> = ["hey", "zeus", "please", "um", "uh"]
            guard prefixWords.allSatisfy({ filler.contains($0) }) else { continue }
            var rest = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix(":") { rest.removeFirst() }
            rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = rest.last, ".,!?".contains(last) { rest.removeLast() }
            rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// Nil when the title is blank. A missing due line stays out of the sentence.
    public static func added(title: String, when: String) -> String? {
        guard let title = trimmed(title) else { return nil }
        if let when = trimmed(when) { return "Added \(title) for \(when)." }
        return "Added \(title)."
    }

    /// "Friday" for a day, "Fri 5:00 PM" when a time was said.
    public static func whenLine(_ date: Date, hasTime: Bool, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = hasTime ? "EEE h:mm a" : "EEEE"
        return formatter.string(from: date)
    }

    private static func trimmed(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ReminderDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var title: String
    public var when: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, title: String, when: String) {
        self.draw = draw
        self.schedule = schedule
        self.title = title
        self.when = when
    }

    /// Nil when the title is blank. A blank due line is left off.
    public static func plan(title: String, when: String) -> ReminderDraw? {
        guard let title = clean(title) else { return nil }
        return make(cards: [title, clean(when)].compactMap { $0 }, title: title, when: clean(when) ?? "")
    }

    public static func access() -> ReminderDraw {
        make(cards: ["Access"], title: "", when: "")
    }

    public static func notSaved() -> ReminderDraw {
        make(cards: ["Not saved"], title: "", when: "")
    }

    /// The short line beside the bolt. The first beat says Reminder.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Reminder" }
        if last >= 2, !when.isEmpty { return Self.shortLine(when) }
        if !title.isEmpty { return Self.shortLine(title) }
        return last >= 1 ? (drawCard(at: 1) ?? "Reminder") : "Reminder"
    }

    /// Where the bolt sits: the ring first, then the newest card.
    public func guideBolt(at elapsed: TimeInterval) -> TalkDraw.Point? {
        let shown = Set(schedule.revealed(at: elapsed))
        let marks = draw.marks.filter { shown.contains($0.at) }
        guard let beat = marks.map(\.at).max() else { return nil }
        let placed = marks.filter { $0.at == beat }.compactMap { mark -> (Int, TalkDraw.Point)? in
            guard let point = Self.anchor(of: mark) else { return nil }
            return (Self.preference(mark), point)
        }
        return placed.min { $0.0 < $1.0 }?.1
    }

    private func drawCard(at beat: Int) -> String? {
        draw.marks.first { mark in
            mark.at == beat
        }.flatMap { mark in
            if case .card(_, let text) = mark.shape { return text }
            return nil
        }
    }

    private static func make(cards: [String], title: String, when: String) -> ReminderDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Reminder"), at: 0),
        ]
        for (index, text) in cards.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ReminderDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), title: title, when: when)
    }

    private static func clean(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
    }

    private static func shortLine(_ raw: String) -> String {
        var current = ""
        for word in raw.split(whereSeparator: \.isWhitespace) {
            let piece = String(word)
            let next = current.isEmpty ? piece : current + " " + piece
            if next.count > 40 { break }
            current = next
        }
        let line = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? String(raw.prefix(40)) : line
    }

    private static func preference(_ mark: TalkDraw.Mark) -> Int {
        switch mark.shape {
        case .ring: return 0
        case .arrow: return 1
        case .ink: return 2
        case .card: return 3
        }
    }

    private static func anchor(of mark: TalkDraw.Mark) -> TalkDraw.Point? {
        switch mark.shape {
        case .ring(let center, let radius):
            guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else { return nil }
            return center
        case .arrow(let from, let to):
            let point = TalkDraw.Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            guard point.x.isFinite, point.y.isFinite else { return nil }
            return point
        case .ink(let points):
            return points.last
        case .card(let origin, _):
            guard origin.x.isFinite, origin.y.isFinite else { return nil }
            return origin
        }
    }
}
