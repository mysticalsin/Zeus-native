import Foundation

/// Resolves spoken pointing words ("this", "that", "here", "these") to a target candidate.
///
/// Evidence is what the pointer did, already in delivered-image pixels: strokes (each already mapped
/// to a candidate or none), dwells and the release point. With word timing from real ASR, a word
/// takes the evidence closest in time. Without timing (the current on-device path returns text only)
/// the k-th deictic word takes the k-th piece of evidence in time order, and extra words reuse the
/// last. Timing is never estimated from word counts.
public enum PointingDeixis {
    public struct Word: Equatable, Sendable {
        public var text: String
        /// Seconds from audio start, from real ASR segments. nil when the engine gave none.
        public var start: Double?
        public init(text: String, start: Double? = nil) { self.text = text; self.start = start }
    }

    public struct Evidence: Equatable, Sendable {
        /// Seconds from audio start.
        public var time: Double
        public var candidateID: String?
        public init(time: Double, candidateID: String?) { self.time = time; self.candidateID = candidateID }
    }

    public static let deicticWords: Set<String> = [
        "this", "that", "these", "those", "here", "there",
        "ceci", "cela", "ça", "ca", "ce", "cet", "cette", "ces", "ici", "là",
    ]
    /// A timed word only binds to evidence within this many seconds.
    public static let window = 1.2

    public static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    public static func isDeictic(_ word: String) -> Bool { deicticWords.contains(normalized(word)) }

    /// Splits a transcript on whitespace into untimed words.
    public static func words(in transcript: String) -> [Word] {
        transcript.split(whereSeparator: { $0.isWhitespace }).map { Word(text: String($0)) }
    }

    public static func resolve(words: [Word], evidence: [Evidence],
                               validIDs: Set<String>) -> [PointingContext.Deixis] {
        let usable = evidence.filter { $0.time.isFinite && ($0.candidateID.map(validIDs.contains) ?? false) }
            .sorted { $0.time < $1.time }
        let deictic = words.filter { isDeictic($0.text) }
        guard !deictic.isEmpty, !usable.isEmpty else {
            return Array(deictic.prefix(PointingContext.maxDeixis)).map { .init(word: normalized($0.text), candidateID: nil) }
        }
        var out: [PointingContext.Deixis] = []
        for (index, word) in deictic.enumerated() {
            let id: String?
            if let start = word.start, start.isFinite {
                let nearest = usable.min { abs($0.time - start) < abs($1.time - start) }
                id = nearest.flatMap { abs($0.time - start) <= window ? $0.candidateID : nil }
            } else {
                id = usable[min(index, usable.count - 1)].candidateID
            }
            out.append(.init(word: normalized(word.text), candidateID: id))
        }
        return Array(out.prefix(PointingContext.maxDeixis))
    }
}
