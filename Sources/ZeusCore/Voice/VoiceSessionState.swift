import Foundation

// TODO: a later slice should make read-aloud engine availability an explicit state: unavailable, downloading, ready, or failed.

public indirect enum VoiceSessionEvent: Equatable, Hashable, Sendable {
    case start
    case started
    case push
    case close
    case closed
    case interrupt
    case deviceChanged
    case fail(VoiceSessionError)

    var shape: VoiceSessionEventShape {
        switch self {
        case .start: .start
        case .started: .started
        case .push: .push
        case .close: .close
        case .closed: .closed
        case .interrupt: .interrupt
        case .deviceChanged: .deviceChanged
        case .fail: .fail
        }
    }

    /// One value of every event. `fail` carries `failure`, so the list stays finite.
    static func everyCase(failure: VoiceSessionError) -> [VoiceSessionEvent] {
        VoiceSessionEventShape.allCases.map { shape in
            switch shape {
            case .start: .start
            case .started: .started
            case .push: .push
            case .close: .close
            case .closed: .closed
            case .interrupt: .interrupt
            case .deviceChanged: .deviceChanged
            case .fail: .fail(failure)
            }
        }
    }
}

enum VoiceSessionEventShape: CaseIterable, Equatable, Sendable {
    case start, started, push, close, closed, interrupt, deviceChanged, fail
}

public indirect enum VoiceSessionError: Error, Equatable, Hashable, Sendable {
    case illegalTransition(from: VoiceSessionState, event: VoiceSessionEvent)
    case badFrameSize(expected: Int, got: Int)
    case emptyFrameList
}

public indirect enum VoiceSessionState: Sendable, Equatable, Hashable {
    case idle
    case starting
    case streaming
    case closing
    case closed
    case failed(VoiceSessionError)

    var shape: VoiceSessionStateShape {
        switch self {
        case .idle: .idle
        case .starting: .starting
        case .streaming: .streaming
        case .closing: .closing
        case .closed: .closed
        case .failed: .failed
        }
    }

    /// One value of every state. `failed` carries `failure`, so the list stays finite.
    static func everyCase(failure: VoiceSessionError) -> [VoiceSessionState] {
        VoiceSessionStateShape.allCases.map { shape in
            switch shape {
            case .idle: .idle
            case .starting: .starting
            case .streaming: .streaming
            case .closing: .closing
            case .closed: .closed
            case .failed: .failed(failure)
            }
        }
    }

    /// `closed` and `failed` are terminal: every event from them is refused.
    /// `fail` is legal from `idle`, and from every other state that is not terminal.
    /// A close from `idle` goes straight to `closed`. A close from `starting` stops at `closing`.
    public func next(on event: VoiceSessionEvent) throws -> VoiceSessionState {
        switch self {
        case .idle:
            switch event {
            case .start:
                return .starting
            case .close:
                return .closed
            case .fail(let error):
                return .failed(error)
            case .started, .push, .closed, .interrupt, .deviceChanged:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        case .starting:
            switch event {
            case .started:
                return .streaming
            case .close, .interrupt:
                return .closing
            case .deviceChanged:
                return .starting
            case .fail(let error):
                return .failed(error)
            case .start, .push, .closed:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        case .streaming:
            switch event {
            case .push:
                return .streaming
            case .close, .interrupt:
                return .closing
            case .deviceChanged:
                return .streaming
            case .fail(let error):
                return .failed(error)
            case .start, .started, .closed:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        case .closing:
            switch event {
            case .closed:
                return .closed
            case .fail(let error):
                return .failed(error)
            case .start, .started, .push, .close, .interrupt, .deviceChanged:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        case .closed:
            switch event {
            case .start, .started, .push, .close, .closed, .interrupt, .deviceChanged, .fail:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        case .failed:
            switch event {
            case .start, .started, .push, .close, .closed, .interrupt, .deviceChanged, .fail:
                throw VoiceSessionError.illegalTransition(from: self, event: event)
            }
        }
    }
}

enum VoiceSessionStateShape: CaseIterable, Equatable, Sendable {
    case idle, starting, streaming, closing, closed, failed
}
