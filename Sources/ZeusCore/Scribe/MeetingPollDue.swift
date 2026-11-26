import Foundation

/// Whether a meeting-window poll is due. The window walk stays in the app.
public enum MeetingPollDue {
    /// At most one walk every 0.7 seconds.
    public static let interval: TimeInterval = 0.7

    /// True when `now` is at least `interval` after `last`, or the clock moved backwards.
    public static func isDue(now: TimeInterval, last: TimeInterval, interval: TimeInterval = MeetingPollDue.interval) -> Bool {
        now - last >= interval || now < last
    }
}
