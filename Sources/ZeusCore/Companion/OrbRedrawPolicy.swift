import Foundation

/// When the orb may schedule display frames.
///
/// `reduceMotion` is a value the caller already read from the system setting.
/// This type never writes that setting.
public enum OrbRedrawPolicy {
    /// Listening, thinking, speaking, and compacting keep the rate the mascot already presents at.
    public static let activeFramesPerSecond = 120

    /// The quiet pose and Reduce Motion present one still frame and then stop.
    public static func pausesRedraw(visualState: OrbVisualState, reduceMotion: Bool) -> Bool {
        reduceMotion || visualState == .idle
    }
}
