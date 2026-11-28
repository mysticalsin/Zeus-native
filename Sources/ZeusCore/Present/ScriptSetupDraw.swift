import Foundation

/// A spoken check of which apps Zeus may script, and the cards drawn while Zeus answers it.
///
/// Music, Spotify, Keynote, and PowerPoint: allowed, still being checked, or off.
/// Asking macOS stays off this card. A prompt is not raised.
public enum ScriptSetupAsk {
    public static let unread = "I can't read which apps Zeus can script."
    public static let states = ["Allowed", "Checking", "Off"]

    /// True for a direct ask about scripting those apps. Other permission packs are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["which", "apps", "can", "zeus", "script"], ["how", "is", "automation", "set"],
             ["automation", "settings"], ["can", "zeus", "control", "music"],
             ["which", "presentation", "apps", "can", "zeus", "read"], ["is", "automation", "allowed"]:
            return true
        default:
            return false
        }
    }

    /// Four known states use that sentence. Anything else is unread.
    public static func line(music: String, spotify: String, keynote: String, powerpoint: String) -> String {
        guard known(music: music, spotify: spotify, keynote: keynote, powerpoint: powerpoint) else { return unread }
        return "\(bit("Music", music)), \(bit("Spotify", spotify)), \(bit("Keynote", keynote)), and \(bit("PowerPoint", powerpoint))."
    }

    public static func known(music: String, spotify: String, keynote: String, powerpoint: String) -> Bool {
        states.contains(music) && states.contains(spotify) && states.contains(keynote) && states.contains(powerpoint)
    }

    private static func bit(_ name: String, _ value: String) -> String {
        switch value {
        case "Allowed": "\(name) is allowed"
        case "Checking": "\(name) is still being checked"
        default: "\(name) is off"
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

public struct ScriptSetupDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown states draw Can't. Otherwise Script, then the four apps.
    public static func plan(music: String, spotify: String, keynote: String, powerpoint: String) -> ScriptSetupDraw {
        guard ScriptSetupAsk.known(music: music, spotify: spotify, keynote: keynote, powerpoint: powerpoint) else { return make(lines: ["Can't"]) }
        return make(lines: ["Music: \(music)", "Spotify: \(spotify)", "Keynote: \(keynote)", "PowerPoint: \(powerpoint)"])
    }

    /// The short line beside the bolt. The first beat says Script.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Script" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Script"
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

    private static func make(lines: [String]) -> ScriptSetupDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Script"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return ScriptSetupDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
