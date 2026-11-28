import Foundation

/// A spoken check of the floating chat window, and the cards drawn while Zeus answers it.
///
/// The window is open or closed. Pins are how many chats stay at the top, from 0 to 999.
/// Chat titles, the notch history, and a new chat stay their own asks. Nothing is opened.
public enum ChatPaneAsk {
    public static let unread = "I can't read the chat window."
    public static let windows = ["Open", "Closed"]

    /// True for a direct ask about the floating chat window. The saved count is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "the", "chat", "window", "open"], ["how", "many", "chats", "are", "pinned"],
             ["chat", "window", "settings"], ["is", "the", "floating", "chat", "open"],
             ["how", "is", "the", "chat", "window", "set"], ["are", "any", "chats", "pinned"]:
            return true
        default:
            return false
        }
    }

    /// A known window and a pin count from 0 to 999 use that sentence. Anything else is unread.
    public static func line(window: String, pins: String) -> String {
        guard let count = knownCount(window: window, pins: pins) else { return unread }
        let open = window == "Open" ? "open" : "closed"
        return "The chat window is \(open), and \(pinWord(count))."
    }

    public static func known(window: String, pins: String) -> Bool {
        knownCount(window: window, pins: pins) != nil
    }

    private static func knownCount(window: String, pins: String) -> Int? {
        guard windows.contains(window), let count = Int(pins), (0...999).contains(count), String(count) == pins else { return nil }
        return count
    }

    private static func pinWord(_ count: Int) -> String {
        switch count {
        case 0: "no chats are pinned"
        case 1: "1 chat is pinned"
        default: "\(count) chats are pinned"
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how is")
        folded = folded.replacingOccurrences(of: "hows", with: "how is")
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

public struct ChatPaneDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown window draws Can't. Otherwise Pane, then the window and the pin count.
    public static func plan(window: String, pins: String) -> ChatPaneDraw {
        guard ChatPaneAsk.known(window: window, pins: pins) else { return make(lines: ["Can't"]) }
        return make(lines: ["Window: \(window)", "Pins: \(pins)"])
    }

    /// The short line beside the bolt. The first beat says Pane.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Pane" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Pane"
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

    private static func make(lines: [String]) -> ChatPaneDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Pane"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ChatPaneDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
