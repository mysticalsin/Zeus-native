import Foundation

/// A spoken "what's playing" ask, and the cards drawn while Zeus answers it.
///
/// The voice says the full line. The screen builds Playing or Paused, then the title,
/// then the artist. With nothing on, the second card is Nothing.
public enum NowPlayingAsk {
    public static let nothing = "Nothing is playing."

    /// True for a direct ask about the track that is on. A play command is not this ask.
    public static func matches(_ text: String) -> Bool {
        let words = words(in: text)
        switch words {
        case ["what", "playing"], ["what", "is", "playing"], ["whats", "playing"],
             ["what", "song", "is", "this"], ["what", "is", "this", "song"],
             ["what", "song", "is", "playing"], ["what", "am", "i", "listening", "to"]:
            return true
        default:
            return false
        }
    }

    /// Nil when the title is blank. A missing artist stays off the line.
    public static func line(title: String, artist: String, playing: Bool) -> String? {
        guard let title = trimmed(title) else { return nil }
        let verb = playing ? "Playing" : "Paused on"
        if let artist = trimmed(artist) { return "\(verb) \(title) by \(artist)." }
        return "\(verb) \(title)."
    }

    private static func words(in text: String) -> [String] {
        let folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        let raw = folded.split { !$0.isLetter && $0 != "'" }.map { token -> String in
            var word = String(token)
            if word.hasSuffix("'s"), word.count > 3 { word = String(word.dropLast(2)) }
            return word.replacingOccurrences(of: "'", with: "")
        }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "zeus", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }

    private static func trimmed(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct NowPlayingDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    /// Playing, Paused, or the Nothing card's lead.
    public var lead: String
    public var title: String?
    public var artist: String?

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, lead: String, title: String?, artist: String?) {
        self.draw = draw
        self.schedule = schedule
        self.lead = lead
        self.title = title
        self.artist = artist
    }

    /// Nil when the title is blank.
    public static func plan(title: String, artist: String, playing: Bool) -> NowPlayingDraw? {
        guard let title = clean(title) else { return nil }
        let artist = clean(artist)
        let lead = playing ? "Playing" : "Paused"
        return make(lead: lead, title: title, artist: artist)
    }

    /// Playing, then Nothing. There is no title.
    public static func nothing() -> NowPlayingDraw {
        make(lead: "Playing", title: "Nothing", artist: nil)
    }

    /// The short line beside the bolt. The first beat names Playing or Paused.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = schedule.revealed(at: elapsed)
        guard let last = shown.last, last >= 1 else { return lead }
        if last == 1 { return title.map(Self.shortLine) ?? lead }
        return artist.map(Self.shortLine) ?? title.map(Self.shortLine) ?? lead
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

    private static func make(lead: String, title: String?, artist: String?) -> NowPlayingDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: lead), at: 0),
        ]
        if let title {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 180), text: title), at: 1))
        }
        if let artist {
            marks.append(.init(shape: .card(origin: .init(x: 920, y: 250), text: artist), at: 2))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return NowPlayingDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes),
                              lead: lead, title: title, artist: artist)
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
        if !line.isEmpty { return line }
        return String(raw.prefix(40))
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
