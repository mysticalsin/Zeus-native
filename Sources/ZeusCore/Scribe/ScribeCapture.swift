import Foundation

/// Identity of one Scribe listening session. Every frame, command and transcript segment carries one,
/// so late work from a replaced or cancelled session can be recognised and dropped.
public struct ScribeSessionID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ScribeAudioSource: Hashable, Sendable {
    case microphone
    case system
}

public enum ScribeMuteState: Hashable, Sendable {
    case unmuted
    case muted
    /// The mute state could not be read. Treated as muted by the gate (fail closed).
    case unknown
}

public enum ScribeCallApp: Hashable, Sendable {
    case teams
    case zoom
    case meet
    case other(String)
}

public struct ScribeAudioFrame: Sendable, Equatable {
    public var session: ScribeSessionID
    public var source: ScribeAudioSource
    public var sequence: UInt64
    public var hostTime: TimeInterval
    public var sampleCount: Int
    public var payload: Data

    public init(
        session: ScribeSessionID,
        source: ScribeAudioSource,
        sequence: UInt64,
        hostTime: TimeInterval,
        sampleCount: Int,
        payload: Data
    ) {
        self.session = session
        self.source = source
        self.sequence = sequence
        self.hostTime = hostTime
        self.sampleCount = sampleCount
        self.payload = payload
    }
}

/// The recording boundary is the capture acknowledgement, after both audio sources have started.
/// Startup/permission buffers must never be replayed as if they were part of the meeting. An unknown
/// timestamp cannot prove that a block belongs after this boundary, so it is withheld too.
public enum ScribeCaptureWindow {
    public static func admits(start: TimeInterval?, duration: TimeInterval, acknowledgedAt: TimeInterval?) -> Bool {
        guard let start, let acknowledgedAt,
              start.isFinite, acknowledgedAt.isFinite, duration.isFinite, duration > 0 else { return false }
        return start >= acknowledgedAt
    }
}

/// Facts reported by a capture provider. The session machine only moves on these, never on timers.
public enum ScribeCaptureEvent: Sendable {
    case captureAcknowledged(ScribeSessionID)
    case captureEnded(ScribeSessionID)
    case failed(ScribeSessionID, any Error)
}

/// Reports whether the user's microphone is muted in the call app. Read once per microphone frame.
public protocol ScribeMicMuteSource: Sendable {
    func currentMuteState() -> ScribeMuteState
}

/// Durable sink for audio frames. Only frames that passed the gate are ever offered to it.
public protocol ScribeFrameStore: Sendable {
    func store(_ frame: ScribeAudioFrame) throws
}

/// Speech recognition sink. Only frames that passed the gate are ever offered to it.
public protocol ScribeTranscriber: Sendable {
    func ingest(_ frame: ScribeAudioFrame)
    func finish(session: ScribeSessionID)
}

/// Source of frames and capture lifecycle events. Real implementations live in the app target.
public protocol ScribeCaptureProvider: Sendable {
    func start(
        session: ScribeSessionID,
        frames: @escaping @Sendable (ScribeAudioFrame) -> Void,
        events: @escaping @Sendable (ScribeCaptureEvent) -> Void
    )
    func stop(session: ScribeSessionID)
}
