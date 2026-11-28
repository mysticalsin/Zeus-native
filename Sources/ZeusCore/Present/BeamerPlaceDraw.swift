import Foundation

/// A spoken Beamer check, and the cards drawn while Zeus answers it.
///
/// The voice says where the keyboard is, the same way the Continuity tab does.
/// Pausing or starting Beamer stays a command.
public enum BeamerPlaceAsk {
    public static let unread = "I can't see Beamer."
    public static let phases = ["Not installed", "Not running", "Needs access", "Paused", "This Mac", "Driving", "Driven"]

    /// True for a direct ask about where the keyboard is. Sound output is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["where", "is", "my", "keyboard"], ["where", "is", "the", "keyboard"],
             ["where", "is", "my", "mouse"], ["where", "is", "the", "pointer"],
             ["where", "is", "my", "pointer"], ["where", "is", "my", "input"],
             ["how", "is", "beamer"], ["is", "beamer", "on"], ["is", "beamer", "running"],
             ["beamer"]:
            return true
        default:
            return false
        }
    }

    /// A known phase uses that sentence. Driving and driven name the machine. Anything else is unread.
    public static func line(phase: String, name: String = "") -> String {
        switch phase {
        case "Not installed": return "Beamer is not installed."
        case "Not running": return "Beamer is not running."
        case "Needs access": return "Beamer needs Accessibility."
        case "Paused": return "Crossing is paused."
        case "This Mac": return "Input is on this Mac."
        case "Driving":
            let shown = clipped(name)
            return shown.isEmpty ? unread : "Your keyboard and mouse are on \(shown)."
        case "Driven":
            let shown = clipped(name)
            return shown.isEmpty ? unread : "\(shown) is driving this Mac."
        default:
            return unread
        }
    }

    private static func clipped(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > TalkDraw.maxTextCharacters else { return flat }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "where's", with: "where is")
        folded = folded.replacingOccurrences(of: "wheres", with: "where is")
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct BeamerPlaceDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// An unknown phase draws Can't. Driving and driven draw the machine. The other phases draw their word.
    public static func plan(phase: String, name: String = "") -> BeamerPlaceDraw {
        guard BeamerPlaceAsk.phases.contains(phase) else { return make(lines: ["Can't"], name: "") }
        if phase == "Driving" || phase == "Driven" {
            let shown = clipped(name)
            guard !shown.isEmpty else { return make(lines: ["Can't"], name: "") }
            return make(lines: [shown], name: shown)
        }
        return make(lines: [phase], name: phase)
    }

    /// The short line beside the bolt. The first beat says Beamer.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Beamer" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Beamer"
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

    private static func clipped(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > TalkDraw.maxTextCharacters else { return flat }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    private static func make(lines: [String], name: String) -> BeamerPlaceDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Beamer"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BeamerPlaceDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
