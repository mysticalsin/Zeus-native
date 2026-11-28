import Foundation

/// How many notifications are waiting, drawn while Zeus says it.
///
/// The voice says the count and the newest app. The screen builds Alerts, then the count, then the app.
/// The title and the body stay off the card. Nothing waiting shows None.
public enum AlertStatusAsk {
    public static let none = "No notifications."
    public static let off = "Notifications are off."
    public static let access = "I need Full Disk Access to read notifications."
    public static let failed = "Notifications couldn't be read."

    /// True for a direct ask about waiting notifications. Turning them on is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["notifications"], ["my", "notifications"], ["any", "notifications"], ["any", "alerts"],
             ["do", "i", "have", "notifications"], ["do", "i", "have", "any", "notifications"],
             ["how", "many", "notifications"], ["how", "many", "alerts"],
             ["what", "notifications", "do", "i", "have"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the count is below one. A blank app stays out of the sentence.
    public static func line(count: Int, app: String) -> String? {
        guard count >= 1 else { return nil }
        if let app = shown(app) {
            if count == 1 { return "1 notification from \(app)." }
            return "\(count) notifications. The newest is from \(app)."
        }
        return count == 1 ? "1 notification." : "\(count) notifications."
    }

    static func shown(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(TalkDraw.maxTextCharacters))
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

public struct AlertStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var count: String
    public var app: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, count: String, app: String) {
        self.draw = draw
        self.schedule = schedule
        self.count = count
        self.app = app
    }

    /// Nil when the count is below one. A blank app is left off.
    public static func plan(count: Int, app: String) -> AlertStatusDraw? {
        guard AlertStatusAsk.line(count: count, app: app) != nil else { return nil }
        let countText = count == 1 ? "1" : "\(count)"
        let app = AlertStatusAsk.shown(app) ?? ""
        let lines = app.isEmpty ? [countText] : [countText, app]
        return make(lines: lines, count: countText, app: app)
    }

    public static func none() -> AlertStatusDraw { make(lines: ["None"], count: "", app: "") }
    public static func off() -> AlertStatusDraw { make(lines: ["Off"], count: "", app: "") }
    public static func access() -> AlertStatusDraw { make(lines: ["Access"], count: "", app: "") }
    public static func failed() -> AlertStatusDraw { make(lines: ["Can't"], count: "", app: "") }

    /// The short line beside the bolt. The first beat says Alerts.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Alerts" }
        if last >= 2, !app.isEmpty { return Self.shortLine(app) }
        if !count.isEmpty { return count }
        return detailWord
    }

    private var detailWord: String {
        for mark in draw.marks {
            if case .card(_, let text) = mark.shape, text != "Alerts" { return text }
        }
        return "None"
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

    private static func make(lines: [String], count: String, app: String) -> AlertStatusDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Alerts"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AlertStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), count: count, app: app)
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
