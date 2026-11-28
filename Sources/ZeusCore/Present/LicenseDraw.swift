import Foundation

/// A spoken license check, and the cards drawn while Zeus answers it.
///
/// The voice says the same title the license row shows.
/// The key stays off this card.
public enum LicenseAsk {
    public static let unread = "I can't read the license."
    public static let yours = "Zeus is yours."
    public static let yoursLast = "Zeus is yours \u{00B7} last day"
    public static let trialLast = "Trial \u{00B7} last day"
    public static let ended = "Your free trial has ended."
    public static let turnedOff = "This license was turned off."

    /// True for a direct ask about the license. The voice choice is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "my", "license"], ["how", "is", "the", "license"],
             ["is", "zeus", "licensed"], ["am", "i", "licensed"],
             ["how", "is", "the", "trial"], ["is", "the", "trial", "on"],
             ["license"], ["my", "license"], ["license", "status"]:
            return true
        default:
            return false
        }
    }

    /// A known page title uses that sentence. Anything else is unread.
    public static func line(word: String) -> String {
        switch word {
        case yours: return "Zeus is yours."
        case yoursLast: return "Zeus is yours. This is the last day."
        case trialLast: return "The trial is on its last day."
        case ended: return "Your free trial has ended."
        case turnedOff: return "This license was turned off."
        default:
            if let days = count(in: word, prefix: "Zeus is yours \u{00B7} ", suffix: " days left") {
                return "Zeus is yours, with \(days) days left."
            }
            if let days = count(in: word, prefix: "Trial \u{00B7} ", suffix: " days left") {
                return "The trial has \(days) days left."
            }
            return unread
        }
    }

    /// True when the title is one the license row can show.
    public static func known(_ word: String) -> Bool {
        line(word: word) != unread
    }

    /// A day count of at least 2. One day is the last-day title, not this form.
    private static func count(in word: String, prefix: String, suffix: String) -> Int? {
        guard word.hasPrefix(prefix), word.hasSuffix(suffix) else { return nil }
        let middle = String(word.dropFirst(prefix.count).dropLast(suffix.count))
        guard let days = Int(middle), days >= 2, days <= 100_000, String(days) == middle else { return nil }
        return days
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

public struct LicenseDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var name: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, name: String) {
        self.draw = draw
        self.schedule = schedule
        self.name = name
    }

    /// An unknown title draws Can't. Otherwise License, then the page title.
    public static func plan(word: String) -> LicenseDraw {
        guard LicenseAsk.known(word) else { return make(lines: ["Can't"], name: "") }
        let shown = clipped(word)
        guard LicenseAsk.known(shown) else { return make(lines: ["Can't"], name: "") }
        return make(lines: [shown], name: shown)
    }

    /// The short line beside the bolt. The first beat says License.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "License" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "License"
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
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > TalkDraw.maxTextCharacters else { return flat }
        return String(flat.prefix(TalkDraw.maxTextCharacters))
    }

    private static func make(lines: [String], name: String) -> LicenseDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "License"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return LicenseDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), name: name)
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
