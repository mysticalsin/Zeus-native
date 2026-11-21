import Foundation

/// How long the notch stays visible to screen capture.
///
/// A shorter boost must not restore the normal policy while a longer boost is still running.
public struct BoostSchedule: Equatable, Sendable {
    public private(set) var deadline: Double?

    public init() {}

    public mutating func boost(now: Double, seconds: Double) -> Double {
        let proposed = now + max(0, seconds)
        // Red: the latest call wins, even when it is shorter than the one already running.
        deadline = proposed
        return proposed
    }

    public func stillBoosted(at now: Double) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }
}
