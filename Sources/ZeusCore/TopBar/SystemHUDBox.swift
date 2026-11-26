import Foundation

/// Level steps, HUD timing, and the brightness poll rate.
/// This type does not read a screen, a pointer, a clock, or a stored setting.
public enum SystemHUDBox {
    public static let coalesceInterval = 0.016
    public static let valueDeltaThreshold = 0.004
    public static let holdAfterChange = 1.2
    public static let easeOut = 0.25
    public static let segmentCount = 16

    /// How often brightness and keyboard backlight are read after a change, then while idle.
    public static let burstInterval = 0.1
    public static let idleInterval = 1.0
    public static let burstWindow = 2.0

    public static func shouldReport(previous: Double, next: Double, threshold: Double = valueDeltaThreshold) -> Bool {
        abs(next - previous) > threshold
    }

    /// A value outside 0...1, including one that is not finite, uses the same clamp as a stored level.
    public static func segmentIndex(for value: Double) -> Int {
        let clamped = max(0, min(1, value))
        return min(segmentCount - 1, Int((clamped * Double(segmentCount)).rounded(.down)))
    }

    public static func filledSegmentCount(for value: Double) -> Int {
        segmentIndex(for: value) + 1
    }

    /// Normal key step is 1/16. The fine step is 1/64.
    public static func stepDelta(fine: Bool) -> Double { fine ? 1.0 / 64.0 : 1.0 / 16.0 }

    public static func steppedValue(_ value: Double, direction: Int, fine: Bool) -> Double {
        let delta = stepDelta(fine: fine) * Double(direction)
        return max(0, min(1, value + delta))
    }

    public static func cueDuration(sinceLastChange: TimeInterval) -> TimeInterval {
        max(0, holdAfterChange - sinceLastChange) + easeOut
    }

    /// Timestamps closer than `window` become one emission at the last time.
    public static func coalesceTimes(_ times: [Date], window: TimeInterval = coalesceInterval) -> [Date] {
        guard var last = times.first else { return [] }
        var out: [Date] = []
        for time in times.dropFirst() {
            if time.timeIntervalSince(last) <= window { last = time; continue }
            out.append(last)
            last = time
        }
        out.append(last)
        return out
    }

    /// A change inside the burst window keeps the fast rate. The window edge, and a value that is
    /// not finite, use the idle rate.
    public static func interval(sinceLastChange: TimeInterval) -> TimeInterval {
        sinceLastChange < burstWindow ? burstInterval : idleInterval
    }

    public static func shouldPoll(brightnessEnabled: Bool, keyboardBacklightEnabled: Bool, displaysAsleep: Bool) -> Bool {
        !displaysAsleep && (brightnessEnabled || keyboardBacklightEnabled)
    }
}
