import Foundation

/// A spoken check of the clipboard chips, and the cards drawn while Zeus answers it.
///
/// The chip is All, Text, Links, Images, or Files. Pins are how many clips stay after a clear.
/// The words on a clip, and how many clips there are, stay their own asks. Nothing is copied or cleared.
public enum ClipboardFilterAsk {
    public static let unread = "I can't read the clipboard filter."
    public static let chips = ["All", "Text", "Links", "Images", "Files"]

    /// True for a direct ask about the clipboard chips. How many clips there are is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "clips", "are", "showing"], ["how", "is", "the", "clipboard", "filter", "set"],
             ["clipboard", "filter", "settings"], ["how", "many", "clips", "are", "pinned"],
             ["is", "the", "clipboard", "showing", "links"], ["which", "clipboard", "chip"]:
            return true
        default:
            return false
        }
    }

    /// A known chip and a pin count from 0 to 999 use that sentence. Anything else is unread.
    public static func line(chip: String, pins: String) -> String {
        guard let count = knownCount(chip: chip, pins: pins) else { return unread }
        return "The clipboard is showing \(chip), and \(pinWord(count))."
    }

    public static func known(chip: String, pins: String) -> Bool {
        knownCount(chip: chip, pins: pins) != nil
    }

    private static func knownCount(chip: String, pins: String) -> Int? {
        guard chips.contains(chip), let count = Int(pins), (0...999).contains(count) else { return nil }
        return count
    }

    private static func pinWord(_ count: Int) -> String {
        switch count {
        case 0: "no clips are pinned"
        case 1: "1 clip is pinned"
        default: "\(count) clips are pinned"
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

public struct ClipboardFilterDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown chip draws Can't. Otherwise Shown, then the chip and the pin count.
    public static func plan(chip: String, pins: String) -> ClipboardFilterDraw {
        guard ClipboardFilterAsk.known(chip: chip, pins: pins) else { return make(lines: ["Can't"]) }
        return make(lines: ["Chip: \(chip)", "Pins: \(pins)"])
    }

    /// The short line beside the bolt. The first beat says Shown.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Shown" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Shown"
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

    private static func make(lines: [String]) -> ClipboardFilterDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Shown"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ClipboardFilterDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
