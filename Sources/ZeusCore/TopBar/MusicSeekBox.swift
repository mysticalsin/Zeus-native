import Foundation

/// Drag position, track time, and the Apple Event that seeks a player.
/// A length that is not positive cannot seek, and a fraction that is not finite cannot seek.
/// A pointer that is not finite, or a line that is not wider than zero, sits at the start.
/// A track longer than one second stops half a second short of the end.
/// A shorter track may seek to its own end. A negative target becomes zero.
/// This type does not read a screen, a pointer, a clock, or a stored setting, and it does not run the script.
public enum MusicSeekBox {
    /// How far short of the end a seek stops, once the track is longer than one second.
    public static let endMargin: Double = 0.5
    /// Tracks longer than this are pulled back from the end by `endMargin`.
    public static let endMarginStartsAfter: Double = 1

    /// 0...1 along the line to seconds, clamped to the track.
    /// Unknown length (0), a negative length, and a fraction that is not finite cannot seek.
    /// A positive infinite length is kept.
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
    /// A length that is not positive draws at the start.
    public static func fraction(elapsed: Double, duration: Double) -> Double {
        duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
    }

    /// Never ends a long track from a seek to the very end: stop `endMargin` short of it.
    /// A track that is not longer than `endMarginStartsAfter` may seek to its own end.
    /// A negative target, a negative length, and an empty length become zero.
    public static func clampedTarget(_ seconds: Double, duration: Double) -> Double {
        let limit = duration > endMarginStartsAfter ? duration - endMargin : duration
        return min(max(seconds, 0), max(limit, 0))
    }

    /// `set player position` for one application id, in seconds, rounded to hundredths.
    /// A negative time is sent as zero. The script is not run here.
    public static func script(bundleID: String, seconds: Double) -> String {
        "tell application id \"\(bundleID)\" to set player position to \(String(format: "%.2f", max(seconds, 0)))"
    }
}
