import Foundation

/// One duplex frame: 3200 `Float` samples at 24 kHz, which is 133 ms.
/// The model speaks one frame ahead of the user. `start` returns that first frame
/// before any user samples arrive.
public struct VoiceFrame: Equatable, Sendable {
    public static let sampleCount = 3_200
    public static let sampleRateHertz = 24_000

    public var samples: [Float]

    public init(samples: [Float]) {
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
    public init(frames: [[Float]]) {}

    public func start() async throws -> VoiceFrame {
        VoiceFrame(samples: [])
    }

    public func push(userFrame: [Float]) async throws -> VoiceFrame {
        _ = userFrame
        return VoiceFrame(samples: [])
    }

    public func close() async {}
}
