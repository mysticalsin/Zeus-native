import Foundation

/// A spoken check of how a Recordly export is set, and the cards drawn while Zeus answers it.
///
/// The format, the size, the quality, and whether the cursor is followed while zoomed.
/// Whether Recordly is recording stays its own ask. Nothing is exported or started.
public enum RecordlyExportAsk {
    public static let unread = "I can't read the Recordly export."
    public static let formats = ["Both", "MP4", "GIF", "None"]
    public static let sizes = ["1080p", "4K"]
    public static let qualities = ["Light", "Balanced", "High"]
    public static let follows = ["On", "Off"]

    /// True for a direct ask about the export. A live recording is not this ask.
    public static func matches(_ text: String) -> Bool {
        switch words(in: text) {
        case ["how", "is", "recordly", "export", "set"], ["which", "recordly", "export"],
             ["what", "is", "the", "recordly", "size"], ["what", "is", "the", "recordly", "quality"],
             ["does", "recordly", "follow", "the", "cursor"], ["recordly", "export", "settings"]:
            return true
        default:
            return false
        }
    }

    /// Four known choices use that sentence. Anything else is unread.
    public static func line(format: String, size: String, quality: String, follow: String) -> String {
        guard known(format: format, size: size, quality: quality, follow: follow) else { return unread }
        return "Recordly exports \(formatWord(format)), at \(size), in \(quality.lowercased()) quality, and \(followWord(follow))."
    }

    public static func known(format: String, size: String, quality: String, follow: String) -> Bool {
        formats.contains(format) && sizes.contains(size) && qualities.contains(quality) && follows.contains(follow)
    }

    private static func formatWord(_ format: String) -> String {
        switch format {
        case "Both": "both MP4 and GIF"
        case "None": "nothing"
        default: format
        }
    }

    private static func followWord(_ follow: String) -> String {
        follow == "On" ? "follows the cursor while zoomed" : "does not follow the cursor"
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

public struct RecordlyExportDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule) {
        self.draw = draw
        self.schedule = schedule
    }

    /// An unknown choice draws Can't. Otherwise Export, then the four choices.
    public static func plan(format: String, size: String, quality: String, follow: String) -> RecordlyExportDraw {
        guard RecordlyExportAsk.known(format: format, size: size, quality: quality, follow: follow) else { return make(lines: ["Can't"]) }
        return make(lines: ["Format: \(format)", "Size: \(size)", "Quality: \(quality)", "Cursor: \(follow)"])
    }

    /// The short line beside the bolt. The first beat says Export.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Export" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Export"
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

    private static func make(lines: [String]) -> RecordlyExportDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Export"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return RecordlyExportDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes))
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
