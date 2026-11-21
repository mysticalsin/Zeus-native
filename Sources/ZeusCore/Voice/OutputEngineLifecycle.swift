import Foundation

/// The output engine that plays a spoken answer.
///
/// `stop` has to stop the engine, not only the player node. Leaving it running holds a headset
/// in its playback profile while the next listen opens.
public struct OutputEngineLifecycle: Equatable, Sendable {
    public private(set) var running = false

    public init() {}

    public mutating func start() {
        running = true
    }

    public mutating func stop() {
        running = false
    }
}
