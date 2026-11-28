import Foundation

/// Who is running, drawn while Zeus says it.
///
/// The voice says the full line. One agent builds Agents, then the name, then the state.
/// Several agents build Agents, then the count, then who is working.
/// With nobody running, the second card is None. Stopping them stays on its own card.
public enum AgentStatusAsk {
    public static let none = "No agents are running."

    /// True for a direct ask about running agents. Stopping them is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["agents"], ["my", "agents"], ["the", "agents"],
             ["what", "are", "my", "agents", "doing"], ["what", "are", "the", "agents", "doing"],
             ["who", "is", "working"], ["any", "agents", "running"],
             ["are", "any", "agents", "running"], ["what", "agents", "are", "running"]:
            return true
        default:
            return false
        }
    }

    /// "Claude is working." "Claude needs you." Nil when the name or the state is blank.
    public static func line(name: String, state: String) -> String? {
        guard let name = shown(name), let state = shown(state) else { return nil }
        if state == "Needs you" { return "\(name) needs you." }
        return "\(name) is \(state.lowercased())."
    }

    /// "2 agents, 1 working." Nil when there are fewer than two.
    public static func line(count: Int, working: Int) -> String? {
        guard count > 1, working >= 0, working <= count else { return nil }
        if working > 0 { return "\(count) agents, \(working) working." }
        return "\(count) agents are running."
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
        folded = folded.replacingOccurrences(of: "who's", with: "who is")
        folded = folded.replacingOccurrences(of: "whos", with: "who is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct AgentStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var title: String
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, title: String, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.title = title
        self.detail = detail
    }

    /// Nil when the name or the state is blank.
    public static func plan(name: String, state: String) -> AgentStatusDraw? {
        guard let name = AgentStatusAsk.shown(name), let state = AgentStatusAsk.shown(state) else { return nil }
        return make(lines: [name, state], title: name, detail: state)
    }

    /// Nil when the count is below two, or the working count does not fit.
    public static func plan(count: Int, working: Int) -> AgentStatusDraw? {
        guard count > 1, working >= 0, working <= count else { return nil }
        let title = "\(count) agents"
        let detail = working == 0 ? "Idle" : "\(working) working"
        return make(lines: [title, detail], title: title, detail: detail)
    }

    public static func none() -> AgentStatusDraw {
        make(lines: ["None"], title: "", detail: "")
    }

    /// The short line beside the bolt. The first beat says Agents.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return "Agents" }
        if last >= 2, !detail.isEmpty { return Self.shortLine(detail) }
        if !title.isEmpty { return Self.shortLine(title) }
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

    private static func make(lines: [String], title: String, detail: String) -> AgentStatusDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Agents"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return AgentStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), title: title, detail: detail)
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
