import Foundation

/// Edits to who said what in a finished meeting. Every function is pure and returns new segments.
public enum ScribeSpeakerEdits {
    /// "Reassign this block to...": one block of lines now belongs to whoever `name` means.
    public static func reassign(
        segmentID: String, to name: String, in segments: [ScribeTranscriptSegment]
    ) -> [ScribeTranscriptSegment] {
        guard let target = ScribeSpeakerNames.target(for: name, in: segments),
              let index = segments.firstIndex(where: { $0.id == segmentID }),
              segments[index].speaker != target else { return segments }
        var result = segments
        result[index].speaker = target
        return result
    }

    /// The words of a segment, split on whitespace.
    public static func words(of segment: ScribeTranscriptSegment) -> [String] {
        segment.text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// "Assign selected words to...": the words in `range` (indices into `words(of:)`) go to `name`; the words
    /// before and after stay with the original speaker. The time is shared out by word count. New pieces get the
    /// id of the block plus ".1", ".2". A range that covers every word is a plain reassign.
    public static func assignWords(
        segmentID: String, range: Range<Int>, to name: String, in segments: [ScribeTranscriptSegment]
    ) -> [ScribeTranscriptSegment] {
        guard let target = ScribeSpeakerNames.target(for: name, in: segments),
              let index = segments.firstIndex(where: { $0.id == segmentID }) else { return segments }
        let segment = segments[index]
        let all = words(of: segment)
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= all.count, segment.speaker != target else {
            return segments
        }
        if range.lowerBound == 0, range.upperBound == all.count { return reassign(segmentID: segmentID, to: name, in: segments) }
        let length = max(0, segment.end - segment.start)
        func piece(_ id: String, _ slice: Range<Int>, _ speaker: ScribeSpeaker) -> ScribeTranscriptSegment {
            var part = segment
            part.id = id
            part.speaker = speaker
            part.text = all[slice].joined(separator: " ")
            part.start = segment.start + length * Double(slice.lowerBound) / Double(all.count)
            part.end = segment.start + length * Double(slice.upperBound) / Double(all.count)
            return part
        }
        var pieces: [ScribeTranscriptSegment] = []
        var extra = 0
        func nextID() -> String { extra += 1; return "\(segment.id).\(extra)" }
        if range.lowerBound > 0 { pieces.append(piece(segment.id, 0..<range.lowerBound, segment.speaker)) }
        pieces.append(piece(range.lowerBound > 0 ? nextID() : segment.id, range, target))
        if range.upperBound < all.count { pieces.append(piece(nextID(), range.upperBound..<all.count, segment.speaker)) }
        var result = segments
        result.replaceSubrange(index...index, with: pieces)
        return result
    }
}

/// Everything an undo has to bring back.
public struct ScribeSpeakerEditState: Equatable, Sendable {
    public var segments: [ScribeTranscriptSegment]
    public var book: ScribeSpeakerBook

    public init(segments: [ScribeTranscriptSegment], book: ScribeSpeakerBook) {
        self.segments = segments
        self.book = book
    }
}

/// The states before each speaker change (rename, merge, reassign, prune), newest last, kept in memory for the
/// session only. Undo brings back exactly the state before the last change.
public struct ScribeSpeakerEditHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var entries: [(title: String, state: ScribeSpeakerEditState)] = []

    public init(capacity: Int = 20) { self.capacity = max(1, capacity) }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.capacity == rhs.capacity && lhs.entries.count == rhs.entries.count
            && zip(lhs.entries, rhs.entries).allSatisfy { $0.title == $1.title && $0.state == $1.state }
    }

    public var canUndo: Bool { !entries.isEmpty }
    public var lastTitle: String? { entries.last?.title }

    public mutating func push(_ title: String, before state: ScribeSpeakerEditState) {
        entries.append((title, state))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public mutating func undo() -> ScribeSpeakerEditState? { entries.popLast()?.state }
    public mutating func clear() { entries = [] }
}

/// Folds tiny, probably spurious voices into the nearest real speaker. Both limits must hold: under 3 % of the
/// talk time and under 3 blocks. A named voice is never folded (a person confirmed or the call window saw it), and a
/// meeting under 30 s of talk is left alone. Each fold is recorded so it can be undone.
public enum ScribeSpeakerPruning {
    public static let maxShare = 0.03
    public static let maxTurns = 3
    public static let minimumTotalSeconds: TimeInterval = 30

    public struct Result: Equatable, Sendable {
        public var segments: [ScribeTranscriptSegment]
        public var folds: [ScribeSpeakerFold]
        public var foldedSpeakers: [ScribeSpeaker]
    }

    private static func channel(_ segment: ScribeTranscriptSegment) -> String { segment.id.hasPrefix("mic-") ? "mic" : "sys" }

    public static func prune(segments: [ScribeTranscriptSegment], book: ScribeSpeakerBook) -> Result {
        let stats = ScribeSpeakerStats(segments: segments)
        guard stats.totalTalkSeconds >= minimumTotalSeconds else { return Result(segments: segments, folds: [], foldedSpeakers: []) }
        let named = Set(book.identities.map { ScribeSpeakerNames.key($0.name) })
        func isNamed(_ speaker: ScribeSpeaker) -> Bool {
            if case .participant(let name) = speaker { return named.contains(ScribeSpeakerNames.key(name)) && !ScribeLiveNaming.isAnonymous(speaker) }
            return false
        }
        let tiny = stats.speakers.filter { entry in
            entry.speaker != .you && entry.speaker != .unknown && !isNamed(entry.speaker)
                && entry.share < maxShare && entry.segmentCount < maxTurns
        }.map(\.speaker)
        let tinySet = Set(tiny)
        let keepers = Set(stats.speakers.map(\.speaker)).subtracting(tinySet)
        guard !tinySet.isEmpty, !keepers.isEmpty else { return Result(segments: segments, folds: [], foldedSpeakers: []) }

        var result = segments
        var folds: [ScribeSpeakerFold] = []
        var folded: [ScribeSpeaker] = []
        for (index, segment) in segments.enumerated() where tinySet.contains(segment.speaker) {
            let candidates = segments.filter { keepers.contains($0.speaker) && channel($0) == channel(segment) }
            guard let nearest = candidates.min(by: { gap($0, segment) < gap($1, segment) }) else { continue }
            result[index].speaker = nearest.speaker
            folds.append(ScribeSpeakerFold(
                segmentID: segment.id, from: ScribeSpeakerRecordLabel(segment.speaker), into: ScribeSpeakerRecordLabel(nearest.speaker)
            ))
            if !folded.contains(segment.speaker) { folded.append(segment.speaker) }
        }
        return Result(segments: result, folds: folds, foldedSpeakers: folded)
    }

    /// Puts folded blocks back, unless the person changed that block since.
    public static func restore(folds: [ScribeSpeakerFold], in segments: [ScribeTranscriptSegment]) -> [ScribeTranscriptSegment] {
        let byID = Dictionary(folds.map { ($0.segmentID, $0) }, uniquingKeysWith: { first, _ in first })
        return segments.map { segment in
            guard let fold = byID[segment.id], segment.speaker == fold.into.speaker else { return segment }
            var back = segment
            back.speaker = fold.from.speaker
            return back
        }
    }

    private static func gap(_ lhs: ScribeTranscriptSegment, _ rhs: ScribeTranscriptSegment) -> TimeInterval {
        if lhs.end <= rhs.start { return rhs.start - lhs.end }
        if rhs.end <= lhs.start { return lhs.start - rhs.end }
        return 0
    }
}

/// The 3-second clip that lets someone recognise a voice, picked from the speaker's longest block.
public enum ScribeVoiceSample {
    public static let clipSeconds: TimeInterval = 3

    public struct Clip: Equatable, Sendable {
        public let segmentID: String
        public let start: TimeInterval
        public let duration: TimeInterval
    }

    /// Nil when the speaker has no block with measurable length.
    public static func clip(for speaker: ScribeSpeaker, in segments: [ScribeTranscriptSegment]) -> Clip? {
        let mine = segments.filter { $0.speaker == speaker && $0.isFinal && $0.end > $0.start }
        guard let best = mine.max(by: { $0.end - $0.start < $1.end - $1.start }) else { return nil }
        let length = best.end - best.start
        let duration = min(clipSeconds, length)
        // Start a little in, so the clip is the middle of the block rather than its first breath.
        let start = best.start + max(0, (length - duration) / 2)
        return Clip(segmentID: best.id, start: start, duration: duration)
    }
}

/// What a speaker row says for a speaker, so the placeholder rule has one home.
public enum ScribeSpeakerCaption {
    /// "Identifying this speaker…" for a voice still called "Speaker N" while naming can still happen.
    public static func name(for speaker: ScribeSpeaker, identifying: Bool) -> (text: String, isPlaceholder: Bool) {
        if identifying, ScribeLiveNaming.isAnonymous(speaker) { return (ScribeLiveNaming.identifying, true) }
        return (speaker.displayName, false)
    }
}
