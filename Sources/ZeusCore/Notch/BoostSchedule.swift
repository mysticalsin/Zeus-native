import Foundation

/// How long the notch stays visible to screen capture.
///
/// A shorter boost must not restore the normal policy while a longer boost is still running.
public struct BoostSchedule: Equatable, Sendable {
    public private(set) var deadline: Double?

    public init() {}

    public mutating func boost(now: Double, seconds: Double) -> Double {
        let proposed = now + max(0, seconds)
        let kept = max(deadline ?? proposed, proposed)
        deadline = kept
        return kept
    }

    public func stillBoosted(at now: Double) -> Bool {
        guard let deadline else { return false }
        return now < deadline
    }
}
