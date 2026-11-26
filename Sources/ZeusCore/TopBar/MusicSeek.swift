import Foundation

/// Scrubbing the progress line: a drag position becomes a time in the track, and the time becomes
/// an Apple Event for the player (`set player position`, seconds, in both Music and Spotify).
/// Each answer is read from `MusicSeekBox`. This type does not run the script.
public enum MusicSeek {
    /// 0...1 along the line to seconds, clamped to the track. Unknown length (0) cannot seek.
    public static func seconds(fraction: Double, duration: Double) -> Double? {
        MusicSeekBox.seconds(fraction: fraction, duration: duration)
    }

    /// Where a pointer at `x` sits on a line `width` wide.
    public static func fraction(x: Double, width: Double) -> Double {
        MusicSeekBox.fraction(x: x, width: width)
    }

    /// Seconds to a fraction of the track for drawing.
    public static func fraction(elapsed: Double, duration: Double) -> Double {
        MusicSeekBox.fraction(elapsed: elapsed, duration: duration)
    }

    /// Never ends the track from a seek to the very end: stop just short of it.
    public static func clampedTarget(_ seconds: Double, duration: Double) -> Double {
        MusicSeekBox.clampedTarget(seconds, duration: duration)
    }

    public static func script(player: NowPlaying.Player, seconds: Double) -> String {
        MusicSeekBox.script(bundleID: player.bundleID, seconds: seconds)
    }
}
