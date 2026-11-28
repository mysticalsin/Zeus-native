import Foundation

/// A spoken agenda ask, and the cards drawn while Zeus answers it.
///
/// The voice says what is left. One event builds Agenda, then the title, then the time.
/// Several build Agenda, then how many are left, then the next title.
/// The next-event card, and joining a meeting, stay on their own paths.
public enum AgendaAsk {
    public static let clear = "The agenda is clear."
    public static let access = "I need Calendar access to read the agenda."

    /// True for a direct ask about the agenda. The next event, and joining it, are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["agenda"], ["my", "agenda"], ["the", "agenda"],
             ["what", "is", "my", "agenda"], ["what", "is", "the", "agenda"],
             ["what", "is", "on", "my", "agenda"], ["what", "is", "on", "the", "agenda"],
             ["what", "is", "coming", "up"], ["what", "coming", "up"],
             ["how", "many", "meetings"], ["how", "many", "meetings", "left"],
             ["how", "many", "meetings", "do", "i", "have"],
             ["how", "many", "events", "left"], ["how", "many", "events", "do", "i", "have"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the count is below one or the title is blank.
    public static func line(count: Int, title: String, when: String, allDay: Bool) -> String? {
        guard count >= 1, let title = cardTitle(title, limit: 200) else { return nil }
        if count == 1 {
            if allDay { return "You have \(title), all day." }
            let when = when.trimmingCharacters(in: .whitespacesAndNewlines)
            if when.isEmpty { return "You have \(title)." }
            return "You have \(title) at \(when)."
        }
        return "You have \(count) events left. Next is \(title)."
    }

    /// A card title, cut on a word once it passes 60 characters.
    public static func cardTitle(_ raw: String, limit: Int = 60) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        if flat.count <= limit { return flat }
        let cut = String(flat.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > 20 {
            return String(cut[..<space])
        }
        return cut
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "what's", with: "what is")
        folded = folded.replacingOccurrences(of: "whats", with: "what is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct AgendaDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
        self.detail = detail
    }

    /// Nil when the count is below one or the title is blank.
    public static func plan(count: Int, title: String, when: String, allDay: Bool) -> AgendaDraw? {
        guard AgendaAsk.line(count: count, title: title, when: when, allDay: allDay) != nil,
              let title = AgendaAsk.cardTitle(title) else { return nil }
        if count == 1 {
            let when = when.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = when.isEmpty && !allDay ? [title] : [title, allDay ? "All day" : when]
            return make(lines: lines, count: title, detail: lines.count > 1 ? lines[1] : "")
        }
        let left = "\(count) left"
        return make(lines: [left, title], count: left, detail: title)
    }

    public static func clear() -> AgendaDraw { make(lines: ["Clear"], count: "", detail: "") }
    public static func access() -> AgendaDraw { make(lines: ["Access"], count: "", detail: "") }

    /// The short line beside the bolt. The first beat says Agenda.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Agenda" }
        if last >= 2, !detail.isEmpty { return detail }
        if !count.isEmpty { return count }
        return detailWord
    }

    private var detailWord: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, text != "Agenda" { return text }
        }
        return "Clear"
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

    private static func make(lines: [String], count: String, detail: String) -> AgendaDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Agenda"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AgendaDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count, detail: detail)
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
