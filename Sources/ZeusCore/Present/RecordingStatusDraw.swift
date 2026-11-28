import Foundation

/// A spoken "are you recording", and the cards drawn while Zeus answers it.
///
/// The voice says whether Scribe or Recordly is recording, and for how long.
/// The words being captured stay off the card. Dictated words stay on their own card.
public enum RecordingAsk {
    public enum Who: Equatable, Sendable { case any, scribe, recordly }

    public static let nothing = "Nothing is recording."
    public static let scribeOff = "Scribe isn't recording."
    public static let recordlyOff = "Recordly isn't recording."
    public static let both = "Scribe and Recordly are recording."

    /// The ask, or nil when this is not a recording question. Starting or stopping one is not this ask.
    public static func who(in text: String) -> Who? {
        switch words(in: text) {
        case ["are", "you", "recording"], ["is", "it", "recording"], ["are", "we", "recording"],
             ["am", "i", "recording"], ["what", "is", "recording"], ["is", "anything", "recording"]:
            return .any
        case ["is", "scribe", "recording"]:
            return .scribe
        case ["is", "recordly", "recording"]:
            return .recordly
        default:
            return nil
        }
    }

    /// "12:04", or "1:02:03" once an hour has passed. A negative count is zero.
    public static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func line(who: Who, scribe: Bool, recordly: Bool, seconds: Int) -> String {
        let clock = clock(seconds)
        switch who {
        case .scribe:
            return scribe ? "Scribe is recording. \(clock)." : scribeOff
        case .recordly:
            return recordly ? "Recordly is recording. \(clock)." : recordlyOff
        case .any:
            switch (scribe, recordly) {
            case (false, false): return nothing
            case (true, false): return "Scribe is recording. \(clock)."
            case (false, true): return "Recordly is recording. \(clock)."
            case (true, true): return both
            }
        }
    }

    /// The cards after Recording. A clock card is included only for one recorder.
    public static func details(who: Who, scribe: Bool, recordly: Bool, seconds: Int) -> [String] {
        let clock = clock(seconds)
        switch who {
        case .scribe:
            return scribe ? ["Scribe", clock] : ["Off"]
        case .recordly:
            return recordly ? ["Recordly", clock] : ["Off"]
        case .any:
            switch (scribe, recordly) {
            case (false, false): return ["Off"]
            case (true, false): return ["Scribe", clock]
            case (false, true): return ["Recordly", clock]
            case (true, true): return ["Both"]
            }
        }
    }

    private static func words(in text: String) -> [String] {
        var folded = text.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .lowercased()
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

public struct RecordingStatusDraw: Equatable, Sendable {
    public var draw: TalkDraw
    public var schedule: ExplainBeatSchedule
    public var detail: String

    public init(draw: TalkDraw, schedule: ExplainBeatSchedule, detail: String) {
        self.draw = draw
        self.schedule = schedule
        self.detail = detail
    }

    public static func plan(who: RecordingAsk.Who, scribe: Bool, recordly: Bool, seconds: Int) -> RecordingStatusDraw {
        let lines = RecordingAsk.details(who: who, scribe: scribe, recordly: recordly, seconds: seconds)
        return make(lines: lines, detail: lines.last ?? "Off")
    }

    /// The short line beside the bolt. The first beat says Recording.
    public func boltCaption(at elapsed: TimeInterval) -> String {
        let shown = Set(schedule.revealed(at: elapsed))
        let cards = draw.marks.compactMap { mark -> (Int, String)? in
            guard shown.contains(mark.at), case .card(_, let text) = mark.shape, text != "Recording" else { return nil }
            return (mark.at, text)
        }
        return cards.max { $0.0 < $1.0 }?.1 ?? "Recording"
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

    private static func make(lines: [String], detail: String) -> RecordingStatusDraw {
        var marks: [TalkDraw.Mark] = [
            .init(shape: .ring(center: .init(x: 320, y: 320), radius: 36), at: 0),
            .init(shape: .card(origin: .init(x: 180, y: 160), text: "Recording"), at: 0),
        ]
        for (index, text) in lines.enumerated() {
            let y = 180.0 + Double(index) * 70
            marks.append(.init(shape: .card(origin: .init(x: 920, y: y), text: text), at: 1 + index))
        }
        let draw = TalkDrawParser.parse(TalkDraw(screen: 1, marks: marks).json)
            ?? TalkDraw(screen: 1, marks: marks)
        let indexes = Array(Set(draw.marks.map(\.at))).sorted()
        return RecordingStatusDraw(draw: draw, schedule: ExplainBeatSchedule(indexes: indexes), detail: detail)
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
