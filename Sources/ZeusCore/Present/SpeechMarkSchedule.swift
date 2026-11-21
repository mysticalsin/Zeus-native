import Foundation

/// When a spoken sentence actually starts, the marks for that sentence become due.
/// The caller passes `(sentenceIndex, audioStartSeconds)`. There is no timer and no words-per-second guess.
public struct SpeechMarkSchedule: Equatable, Sendable {
    public struct Mark: Equatable, Sendable {
        public var id: String
        public var sentenceIndex: Int

        public init(id: String, sentenceIndex: Int) {
            self.id = id
            self.sentenceIndex = sentenceIndex
        }
    }

    public struct Due: Equatable, Sendable {
        public var id: String
        public var sentenceIndex: Int
        public var audioStartSeconds: Double

        public init(id: String, sentenceIndex: Int, audioStartSeconds: Double) {
            self.id = id
            self.sentenceIndex = sentenceIndex
            self.audioStartSeconds = audioStartSeconds
        }
    }

    private var marks: [Mark]
    private var started: [Int: Double] = [:]
    private var cancelled = false

    public init(marks: [Mark]) {
        self.marks = marks
    }

    /// Record that this sentence started in the real audio. The same sentence is applied once.
    public mutating func apply(sentenceIndex: Int, audioStartSeconds: Double) -> [Due] {
        guard !cancelled, audioStartSeconds.isFinite, audioStartSeconds >= 0 else { return [] }
        guard started[sentenceIndex] == nil else { return [] }
        started[sentenceIndex] = audioStartSeconds
        return marks.filter { $0.sentenceIndex == sentenceIndex }.map {
            Due(id: $0.id, sentenceIndex: $0.sentenceIndex, audioStartSeconds: audioStartSeconds)
        }
    }

    /// Marks whose sentence has started at or before `audioTime`. Empty after cancel.
    public func due(at audioTime: Double) -> [Due] {
        guard !cancelled, audioTime.isFinite else { return [] }
        return marks.compactMap { mark in
            guard let start = started[mark.sentenceIndex], start <= audioTime else { return nil }
            return Due(id: mark.id, sentenceIndex: mark.sentenceIndex, audioStartSeconds: start)
        }
    }

    /// No further marks are due, including ones already applied.
    public mutating func cancel() {
        cancelled = true
    }
}
