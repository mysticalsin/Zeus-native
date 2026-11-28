import Foundation

/// A spoken check of per-app sound, and the cards drawn while Zeus answers it.
///
/// Whether shaping is on, whether any apps are saved, and whether any of those apps are shaped.
/// App names stay off the card. Nothing is tapped or changed.
public enum BandSetupAsk {
    public static let unread = "I can't read per-app sound."
    public static let switches = ["On", "Off"]
    public static let saves = ["None", "Chosen", "Unreadable"]
    public static let shaped = ["None", "Some"]

    /// True for a direct ask about per-app sound. Cue volume and the Mac's volume are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["is", "per", "app", "sound", "on"], ["how", "is", "per", "app", "sound", "set"],
             ["per", "app", "sound", "settings"], ["are", "any", "apps", "shaped"],
             ["does", "zeus", "shape", "sound", "per", "app"], ["how", "is", "the", "equaliser", "set"]:
            return true
        default:
            return false
        }
    }

    /// A known switch, save, and shaped list use that sentence. An empty or unreadable book cannot have shaped apps.
    public static func line(shape: String, saved: String, shaped: String) -> String {
        guard known(shape: shape, saved: saved, shaped: shaped) else { return unread }
        return "Per-app sound is \(word(shape)), \(savedWord(saved)), and \(shapedWord(shaped))."
    }

    public static func known(shape: String, saved: String, shaped: String) -> Bool {
        guard switches.contains(shape), saves.contains(saved), self.shaped.contains(shaped) else { return false }
        return saved == "Chosen" || shaped == "None"
    }

    private static func word(_ value: String) -> String { value == "On" ? "on" : "off" }

    private static func savedWord(_ saved: String) -> String {
        switch saved {
        case "None": "no apps are saved"
        case "Chosen": "apps are saved"
        default: "the saved apps could not be read"
        }
    }

    private static func shapedWord(_ shaped: String) -> String {
        shaped == "Some" ? "some are shaped" : "none are shaped"
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

public struct BandSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Bands, then the switch, the saved list, and whether any are shaped.
    public static func plan(shape: String, saved: String, shaped: String) -> BandSetupDraw {
        guard BandSetupAsk.known(shape: shape, saved: saved, shaped: shaped) else { return make(lines: ["Can't"]) }
        return make(lines: ["Shape: \(shape)", "Saved: \(saved)", "Shaped: \(shaped)"])
    }

    /// The short line beside the bolt. The first beat says Bands.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Bands" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Bands"
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

    private static func make(lines: [String]) -> BandSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Bands"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return BandSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
