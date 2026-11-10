import Foundation

/// Scrubbing the progress line: a drag position becomes a time in the track, and the time becomes
/// an Apple Event for the player (`set player position`, seconds, in both Music and Spotify).
public enum MusicSeek {
    /// 0...1 along the line to seconds, clamped to the track. Unknown length (0) cannot seek.
    public static func seconds(fraction: Double, duration: Double) -> Double? {
        guard duration > 0, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1) * duration
    }

    /// Where a pointer at `x` sits on a line `width` wide.
    public static func fraction(x: Double, width: Double) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return min(max(x / width, 0), 1)
    }

    /// Seconds to a fraction of the track for drawing.
    public static func fraction(elapsed: Double, duration: Double) -> Double {
        duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
    }

    /// Never ends the track from a seek to the very end: stop just short of it.
    public static func clampedTarget(_ seconds: Double, duration: Double) -> Double {
        let limit = duration > 1 ? duration - 0.5 : duration
        return min(max(seconds, 0), max(limit, 0))
    }

    public static func script(player: NowPlaying.Player, seconds: Double) -> String {
        "tell application id \"\(player.bundleID)\" to set player position to \(String(format: "%.2f", max(seconds, 0)))"
    }
}
