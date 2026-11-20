import Foundation

// TODO: a later slice should make read-aloud engine availability an explicit state: unavailable, downloading, ready, or failed.

public indirect enum VoiceSessionEvent: Equatable, Hashable, Sendable {
    case start
    case started
    case push
    case close
    case closed
    case fail(VoiceSessionError)
}

public indirect enum VoiceSessionError: Error, Equatable, Hashable, Sendable {
    case illegalTransition(from: VoiceSessionState, event: VoiceSessionEvent)
    case badFrameSize(expected: Int, got: Int)
}

public indirect enum VoiceSessionState: Sendable, Equatable, Hashable {
    case idle
    case starting
    case streaming
    case closing
    case closed
    case failed(VoiceSessionError)

    /// Placeholder. Every event is refused until the table is filled in.
    public func next(on event: VoiceSessionEvent) throws -> VoiceSessionState {
        throw VoiceSessionError.illegalTransition(from: self, event: event)
    }
}
