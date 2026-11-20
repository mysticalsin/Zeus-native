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

    public func next(on event: VoiceSessionEvent) throws -> VoiceSessionState {
        switch (self, event) {
        case (.idle, .start):
            return .starting
        case (.starting, .started):
            return .streaming
        case (.streaming, .push):
            return .streaming
        case (.streaming, .close):
            return .closing
        case (.closing, .closed):
            return .closed
        case (.idle, .fail(let error)),
             (.starting, .fail(let error)),
             (.streaming, .fail(let error)),
             (.closing, .fail(let error)):
            return .failed(error)
        default:
            throw VoiceSessionError.illegalTransition(from: self, event: event)
        }
    }
}
