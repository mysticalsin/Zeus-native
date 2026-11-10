import Foundation

public enum ScribeSpeaker: Equatable, Hashable, Sendable {
    case you
    case participant(String)
    case unknown

    /// Microphone audio is always the user. System audio is a participant when a label is known.
    public static func forSource(_ source: ScribeAudioSource, label: String? = nil) -> ScribeSpeaker {
        switch source {
        case .microphone:
            return .you
        case .system:
            let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? .unknown : .participant(trimmed)
        }
    }

    public var displayName: String {
        switch self {
        case .you: return "You"
        case .participant(let label): return label
        case .unknown: return "Unknown"
        }
    }
}

public struct ScribeTranscriptSegment: Equatable, Sendable {
    public var id: String
    public var session: ScribeSessionID
    public var speaker: ScribeSpeaker
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var isFinal: Bool

    public init(
        id: String,
        session: ScribeSessionID,
        speaker: ScribeSpeaker,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        isFinal: Bool
    ) {
        self.id = id
        self.session = session
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
        self.isFinal = isFinal
    }
}

public enum ScribeTranscriptUpdate: Equatable, Sendable {
    case inserted
    case replaced
    /// The segment id already holds a final segment; final text is never overwritten.
    case ignoredLocked
    case rejectedSession
    case rejectedFinalized
    case rejectedInvalid
}

public struct ScribeTranscript: Equatable, Sendable {
    public let session: ScribeSessionID
    public private(set) var segments: [ScribeTranscriptSegment] = []
    public private(set) var isFinalized = false

    public init(session: ScribeSessionID) {
        self.session = session
    }

    public var finalSegments: [ScribeTranscriptSegment] { segments.filter(\.isFinal) }

    @discardableResult
    public mutating func upsert(_ segment: ScribeTranscriptSegment) -> ScribeTranscriptUpdate {
        guard segment.session == session else { return .rejectedSession }
        guard !isFinalized else { return .rejectedFinalized }
        guard segment.start.isFinite, segment.end.isFinite, segment.end >= segment.start else {
            return .rejectedInvalid
        }
        if let index = segments.firstIndex(where: { $0.id == segment.id }) {
            if segments[index].isFinal { return .ignoredLocked }
            segments[index] = segment
            sortSegments()
            return .replaced
        }
        segments.append(segment)
        sortSegments()
        return .inserted
    }

    /// Provisional segments that never received a final result. Still inspectable after `finalize()`,
    /// but never part of final output, exports or generated notes.
    public var unresolvedSegments: [ScribeTranscriptSegment] { segments.filter { !$0.isFinal } }

    /// Locks the transcript against new segments. Finality flags are preserved: provisional text is
    /// NOT promoted to final, so unconfirmed ASR output cannot leak into notes or exports.
    public mutating func finalize() {
        isFinalized = true
    }

    /// Compatibility export for the existing `MeetingTranscript` consumers.
    public func meetingTranscript(includeProvisional: Bool = false) -> MeetingTranscript {
        let lines = segments
            .filter { includeProvisional || $0.isFinal }
            .map { MeetingTranscriptLine(start: $0.start, speaker: $0.speaker.displayName, text: $0.text) }
        return MeetingTranscript(lines: lines)
    }

    private mutating func sortSegments() {
        segments.sort { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id
        }
    }
}
