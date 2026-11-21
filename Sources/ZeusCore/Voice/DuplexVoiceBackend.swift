import Foundation

/// One duplex frame: 3200 `Float` samples at 24 kHz, which is 133 ms.
/// The model speaks one frame ahead of the user. `start` returns that first frame
/// before any user samples arrive.
public struct VoiceFrame: Equatable, Sendable {
    public static let sampleCount = 3_200
    public static let sampleRateHertz = 24_000

    public var samples: [Float]

    public init(samples: [Float]) throws {
        guard samples.count == Self.sampleCount else {
            throw VoiceSessionError.badFrameSize(expected: Self.sampleCount, got: samples.count)
        }
        self.samples = samples
    }
}

public protocol DuplexVoiceBackend: Sendable {
    var state: VoiceSessionState { get async }
    func start() async throws -> VoiceFrame
    func push(userFrame: [Float]) async throws -> VoiceFrame
    func close() async
}

/// Canned frames for tests. Not a model and not a download.
public actor FakeDuplexVoiceBackend: DuplexVoiceBackend {
    private let frames: [VoiceFrame]
    private let beforeStarted: (@Sendable () async -> Void)?
    private var session = VoiceSessionState.idle
    private var nextReply = 1

    public var state: VoiceSessionState { session }

    public init(frames: [[Float]], beforeStarted: (@Sendable () async -> Void)? = nil) throws {
        let built = try frames.map { try VoiceFrame(samples: $0) }
        guard !built.isEmpty else { throw VoiceSessionError.emptyFrameList }
        self.frames = built
        self.beforeStarted = beforeStarted
    }

    public func start() async throws -> VoiceFrame {
        session = try session.next(on: .start)
        await beforeStarted?()
        guard session == .starting else {
            if session == .closing {
                session = try session.next(on: .closed)
            }
            throw VoiceSessionError.illegalTransition(from: session, event: .started)
        }
        session = try session.next(on: .started)
        nextReply = 1
        return frames[0]
    }

    public func push(userFrame: [Float]) async throws -> VoiceFrame {
        let advanced = try session.next(on: .push)
        _ = try VoiceFrame(samples: userFrame)
        session = advanced
        let reply = nextReply < frames.count ? frames[nextReply] : frames[frames.count - 1]
        if nextReply < frames.count { nextReply += 1 }
        return reply
    }

    public func close() async {
        let previous = session
        guard let next = try? session.next(on: .close) else { return }
        session = next
        // Streaming has no load left to finish the close. Starting does: start applies `.closed`.
        if previous == .streaming, let done = try? session.next(on: .closed) {
            session = done
        }
    }
}
