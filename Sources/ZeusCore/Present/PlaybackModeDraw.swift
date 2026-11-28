import Foundation

/// A spoken check of shuffle and repeat, and the cards drawn while Zeus answers it.
///
/// Each is on, off, or not read yet. Repeat can also be all or one song.
/// The track and the music source stay their own asks. Nothing is changed.
public enum PlaybackModeAsk {
    public static let unread = "I can't read shuffle and repeat."
    public static let shuffles = ["On", "Off", "Unknown"]
    public static let repeats = ["Off", "All", "One", "Unknown"]

    /// True for a direct ask about shuffle or repeat. The track is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "shuffle", "on"], ["how", "is", "repeat", "set"],
             ["how", "is", "playback", "set"], ["music", "mode", "settings"],
             ["is", "repeat", "on"], ["which", "repeat", "mode"]:
            return true
        default:
            return false
        }
    }

    /// Two known modes use that sentence. Anything else is unread.
    public static func line(shuffle: String, repeatMode: String) -> String {
        guard known(shuffle: shuffle, repeatMode: repeatMode) else { return unread }
        return "\(shuffleWord(shuffle)), and \(repeatWord(repeatMode))."
    }

    public static func known(shuffle: String, repeatMode: String) -> Bool {
        shuffles.contains(shuffle) && repeats.contains(repeatMode)
    }

    private static func shuffleWord(_ shuffle: String) -> String {
        switch shuffle {
        case "On": "Shuffle is on"
        case "Off": "Shuffle is off"
        default: "Shuffle has not been read"
        }
    }

    private static func repeatWord(_ repeatMode: String) -> String {
        switch repeatMode {
        case "Off": "repeat is off"
        case "All": "repeat is all"
        case "One": "repeat is one song"
        default: "repeat has not been read"
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
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

public struct PlaybackModeDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown mode draws Can't. Otherwise Modes, then shuffle and repeat.
    public static func plan(shuffle: String, repeatMode: String) -> PlaybackModeDraw {
        guard PlaybackModeAsk.known(shuffle: shuffle, repeatMode: repeatMode) else { return make(lines: ["Can't"]) }
        return make(lines: ["Shuffle: \(shuffle)", "Repeat: \(repeatMode)"])
    }

    /// The short line beside the bolt. The first beat says Modes.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Modes" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Modes"
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

    private static func make(lines: [String]) -> PlaybackModeDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Modes"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return PlaybackModeDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
