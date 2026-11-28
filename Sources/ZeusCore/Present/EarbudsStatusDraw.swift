import Foundation

/// A spoken earbud connection, and the cards drawn while Zeus answers it.
///
/// The voice says whether the Mac's sound output is a Bluetooth device.
/// The charge stays on the notch cue. Screens, tiling, and what's playing stay on their own cards.
public enum EarbudsStatusAsk {
    public static let unread = "I can't see the sound output."

    /// True for a direct ask about earbuds or AirPods. A track request is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["are", "my", "earbuds", "connected"], ["are", "the", "earbuds", "connected"],
             ["are", "earbuds", "connected"], ["are", "my", "earbuds", "on"],
             ["are", "the", "earbuds", "on"], ["are", "earbuds", "on"],
             ["earbuds", "connected"], ["earbuds"],
             ["are", "my", "airpods", "connected"], ["are", "the", "airpods", "connected"],
             ["are", "airpods", "connected"], ["are", "my", "airpods", "on"],
             ["are", "the", "airpods", "on"], ["are", "airpods", "on"],
             ["airpods", "connected"], ["airpods"],
             ["how", "are", "my", "earbuds"], ["how", "are", "the", "earbuds"],
             ["how", "are", "earbuds"], ["how", "are", "my", "airpods"],
             ["how", "are", "the", "airpods"], ["how", "are", "airpods"]:
            return true
        default:
            return false
        }
    }

    /// The name that fits on the card. Blank is nil. The word Earbuds is the title, not a name.
    public static func cardName(_ raw: String) -> String? {
        let flat = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty, flat != "Earbuds" else { return nil }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    /// Connected names the device when one is shown. Disconnected and unread do not.
    public static func line(connected: Bool?, name: String) -> String {
        guard let connected else { return unread }
        if !connected { return "Earbuds disconnected." }
        guard let name = cardName(name) else { return "Earbuds connected." }
        return "\(name) connected."
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
        folded = folded.replacingOccurrences(of: "how's", with: "how are")
        folded = folded.replacingOccurrences(of: "hows", with: "how are")
        let raw = folded.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { String($0).replacingOccurrences(of: "'", with: "") }
        var words = raw.filter { !$0.isEmpty }
        let lead: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        let tail: Set<String> = ["please", "now", "thanks"]
        while let first = words.first, lead.contains(first), words.count > 1 { words.removeFirst() }
        while let last = words.last, tail.contains(last), words.count > 1 { words.removeLast() }
        return words
    }
}

public struct EarbudsStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// Unread draws Can't. Otherwise the notch word, then the device name when connected.
    public static func plan(connected: Bool?, name: String) -> EarbudsStatusDraw {
        guard let connected else { return make(lines: ["Can't"], name: "") }
        if !connected { return make(lines: ["Disconnected"], name: "") }
        let name = EarbudsStatusAsk.cardName(name) ?? ""
        let lines = name.isEmpty ? ["Connected"] : ["Connected", name]
        return make(lines: lines, name: name)
    }

    /// The short line beside the bolt. The first beat says Earbuds.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Earbuds" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Earbuds"
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

    private static func make(lines: [String], name: String) -> EarbudsStatusDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Earbuds"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return EarbudsStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
