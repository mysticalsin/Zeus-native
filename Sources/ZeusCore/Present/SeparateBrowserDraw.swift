import Foundation

/// A spoken check of the separate browser, and the cards drawn while Zeus answers it.
///
/// Whether uv, browser-use, and Chromium are ready, and whether sites are limited.
/// Paths and site names stay off the card. Nothing is downloaded or launched.
public enum SeparateBrowserAsk {
    public static let unread = "I can't read the separate browser."
    public static let tools = ["Ready", "Missing", "Not checked"]

    /// True for a direct ask about the separate browser. The Chrome choice and a running task are not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "the", "separate", "browser", "set"], ["is", "the", "separate", "browser", "ready"],
             ["separate", "browser", "settings"], ["is", "uv", "ready"],
             ["which", "sites", "can", "the", "separate", "browser", "open"], ["how", "is", "browser", "use", "set"]:
            return true
        default:
            return false
        }
    }

    /// Three tool states and Any, or a site count from 1 to 99, use that sentence. Anything else is unread.
    public static func line(uv: String, package: String, browser: String, sites: String) -> String {
        guard known(uv: uv, package: package, browser: browser, sites: sites) else { return unread }
        let reach = sites == "Any" ? "may open any site" : "is limited to \(sites) \(sites == "1" ? "site" : "sites")"
        return "uv is \(word(uv)), browser-use is \(word(package)), Chromium is \(word(browser)), and the separate browser \(reach)."
    }

    public static func known(uv: String, package: String, browser: String, sites: String) -> Bool {
        tools.contains(uv) && tools.contains(package) && tools.contains(browser) && knownSites(sites)
    }

    /// Comma-separated sites, blanks dropped. The names themselves are not returned.
    public static func siteCount(_ stored: String) -> Int {
        stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.count
    }

    private static func knownSites(_ sites: String) -> Bool {
        if sites == "Any" { return true }
        guard let number = Int(sites), (1...99).contains(number), String(number) == sites else { return false }
        return true
    }

    private static func word(_ value: String) -> String {
        switch value {
        case "Ready": "ready"
        case "Missing": "missing"
        default: "not checked"
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

public struct SeparateBrowserDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// Unknown choices draw Can't. Otherwise Separate, then uv, browser-use, Chromium, and the sites.
    public static func plan(uv: String, package: String, browser: String, sites: String) -> SeparateBrowserDraw {
        guard SeparateBrowserAsk.known(uv: uv, package: package, browser: browser, sites: sites) else { return make(lines: ["Can't"]) }
        return make(lines: ["uv: \(uv)", "Package: \(package)", "Chromium: \(browser)", "Sites: \(sites)"])
    }

    /// The short line beside the bolt. The first beat says Separate.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Separate" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Separate"
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

    private static func make(lines: [String]) -> SeparateBrowserDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Separate"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return SeparateBrowserDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
