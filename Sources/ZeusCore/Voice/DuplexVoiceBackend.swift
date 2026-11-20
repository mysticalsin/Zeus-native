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
            throw DuplexVoiceError.wrongFrameSize(count: samples.count)
        }
        self.samples = samples
    }
}

public enum DuplexVoiceError: Error, Equatable, Sendable {
    case wrongFrameSize(count: Int)
    case pushBeforeStart
    case pushAfterClose
}

public protocol DuplexVoiceBackend: Sendable {
    func start() async throws -> VoiceFrame
    func push(userFrame: [Float]) async throws -> VoiceFrame
    func close() async
}

/// Canned frames for tests. Not a model and not a download.
public actor FakeDuplexVoiceBackend: DuplexVoiceBackend {
    private let frames: [VoiceFrame]
    private var started = false
    private var closed = false
    private var nextReply = 1

    public init(frames: [[Float]]) throws {
        let built = try frames.map { try VoiceFrame(samples: $0) }
        guard !built.isEmpty else { throw DuplexVoiceError.wrongFrameSize(count: 0) }
        self.frames = built
    }

    public func start() async throws -> VoiceFrame {
        started = true
        nextReply = 1
        return frames[0]
    }

    public func push(userFrame: [Float]) async throws -> VoiceFrame {
        if closed { throw DuplexVoiceError.pushAfterClose }
        if !started { throw DuplexVoiceError.pushBeforeStart }
        _ = try VoiceFrame(samples: userFrame)
        let reply = nextReply < frames.count ? frames[nextReply] : frames[frames.count - 1]
        if nextReply < frames.count { nextReply += 1 }
        return reply
    }

    public func close() async {
        closed = true
    }
}
