import Foundation

/// When a spoken sentence actually starts, the marks for that sentence become due.
/// The caller passes `(sentenceIndex, audioStartSeconds)`. A mark with its own due time
/// waits for that time. When no real time exists, the 0.18 s per word fallback is used
/// and disclosed. A mark with no time at all expires instead of waiting forever.
public struct SpeechMarkSchedule: Equatable, Sendable {
    /// Same fallback the speech timeline uses when no word times exist. Real times never use it.
    public static let estimatedSecondsPerWord = 0.18
    /// A mark that never receives a start is dropped after this much audio time.
    public static let missingStartExpirySeconds = 4.0
    public static let estimatedTimingDisclosure = "0.18 s per word"

    public struct Mark: Equatable, Sendable {
        public var id: String
        public var sentenceIndex: Int
        /// Real audio time for this mark. Nil when the caller has no measurement.
        public var dueSeconds: Double?
        /// Used only for the 0.18 s fallback, and only when `dueSeconds` and the sentence start are both missing.
        public var wordIndex: Int?

        public init(id: String, sentenceIndex: Int, dueSeconds: Double? = nil, wordIndex: Int? = nil) {
            self.id = id
            self.sentenceIndex = sentenceIndex
            self.dueSeconds = dueSeconds
            self.wordIndex = wordIndex
        }
    }

    public struct Due: Equatable, Sendable {
        public var id: String
        public var sentenceIndex: Int
        public var audioStartSeconds: Double
        /// True only when `audioStartSeconds` came from the 0.18 s per word fallback.
        public var estimated: Bool
        /// Empty when the time is real. The fallback names itself.
        public var timingDisclosure: String

        public init(id: String, sentenceIndex: Int, audioStartSeconds: Double,
                    estimated: Bool = false, timingDisclosure: String = "") {
            self.id = id
            self.sentenceIndex = sentenceIndex
            self.audioStartSeconds = audioStartSeconds
            self.estimated = estimated
            self.timingDisclosure = timingDisclosure
        }
    }

    private var marks: [Mark]
    private var started: [Int: Double] = [:]
    private var cancelled = false

    public init(marks: [Mark]) {
        self.marks = marks
    }

    public var isCancelled: Bool { cancelled }

    /// Record that this sentence started in the real audio. Returns only the marks of that
    /// sentence whose due time is at or before `audioStartSeconds`. A later timestamp stays hidden.
    /// The same sentence is applied once.
    public mutating func apply(sentenceIndex: Int, audioStartSeconds: Double) -> [Due] {
        guard !cancelled, audioStartSeconds.isFinite, audioStartSeconds >= 0 else { return [] }
        guard started[sentenceIndex] == nil else { return [] }
        started[sentenceIndex] = audioStartSeconds
        return due(at: audioStartSeconds).filter { $0.sentenceIndex == sentenceIndex }
    }

    /// Marks whose due time is at or before `audioTime`. Empty after cancel or barge-in.
    public func due(at audioTime: Double) -> [Due] {
        guard !cancelled, audioTime.isFinite, audioTime >= 0 else { return [] }
        return marks.compactMap { mark in
            guard let timing = timing(of: mark), timing.time <= audioTime else { return nil }
            return Due(id: mark.id, sentenceIndex: mark.sentenceIndex, audioStartSeconds: timing.time,
                       estimated: timing.estimated,
                       timingDisclosure: timing.estimated ? Self.estimatedTimingDisclosure : "")
        }
    }

    /// Marks that still have no time and have not reached the expiry bound.
    public func pendingIDs(at audioTime: Double) -> [String] {
        guard !cancelled, audioTime.isFinite, audioTime >= 0 else { return [] }
        guard audioTime < Self.missingStartExpirySeconds else { return [] }
        return marks.compactMap { mark in
            timing(of: mark) == nil ? mark.id : nil
        }
    }

    /// A barge-in stops every mark that has not been shown and every mark still waiting.
    public mutating func bargeIn() {
        cancel()
    }

    /// No further marks are due, including ones already applied.
    public mutating func cancel() {
        cancelled = true
    }

    private func timing(of mark: Mark) -> (time: Double, estimated: Bool)? {
        if let due = mark.dueSeconds, due.isFinite, due >= 0 {
            return (due, false)
        }
        if let start = started[mark.sentenceIndex] {
            return (start, false)
        }
        if let index = mark.wordIndex, index >= 0 {
            return (Double(index) * Self.estimatedSecondsPerWord, true)
        }
        return nil
    }
}
