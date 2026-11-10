import Foundation

/// Lowers system output volume while Zeus listens or speaks, then restores the exact snapshot (O21).
/// Never unmutes and never raises volume above the snapshot. No-op while muted or volume is 0.
public struct AudioQuiet: Sendable, Equatable {
    public var snapshotVolume: Float
    public var snapshotMuted: Bool
    public var duckedVolume: Float?
    public var applied: Bool

    public init(snapshotVolume: Float, snapshotMuted: Bool, duckedVolume: Float? = nil, applied: Bool = false) {
        self.snapshotVolume = snapshotVolume
        self.snapshotMuted = snapshotMuted
        self.duckedVolume = duckedVolume
        self.applied = applied
    }

    /// True when ducking must not touch output (SILENT MODE / mute-guard).
    public static func isMuteGuardActive(volume: Float, muted: Bool) -> Bool {
        muted || volume <= 0.0001
    }

    /// Returns the volume to set while ducked, or nil when ducking is a no-op.
    public static func duckTarget(snapshotVolume: Float, snapshotMuted: Bool, fraction: Float = 0.35) -> Float? {
        guard !isMuteGuardActive(volume: snapshotVolume, muted: snapshotMuted) else { return nil }
        return max(0, min(snapshotVolume, snapshotVolume * fraction))
    }

    public mutating func beginDuck(fraction: Float = 0.35) -> Float? {
        guard !applied else { return duckedVolume }
        guard let target = Self.duckTarget(snapshotVolume: snapshotVolume, snapshotMuted: snapshotMuted, fraction: fraction) else {
            return nil
        }
        duckedVolume = target
        applied = true
        return target
    }

    /// Volume to restore after ducking. Never above the snapshot and never forces unmute.
    public func restoreVolume(currentVolume: Float, currentMuted: Bool) -> Float? {
        guard applied else { return nil }
        if snapshotMuted || snapshotVolume <= 0.0001 { return nil }
        return snapshotVolume
    }

    public mutating func endDuck() {
        applied = false
        duckedVolume = nil
    }
}
