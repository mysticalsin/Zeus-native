import Foundation

/// How close two frames must be to count as the same. Pure.
public enum TileReadBack {
    /// Points. Accessibility, the window list and an app's own rounding can each differ by a point or two.
    public static let tolerance = 2.0

    /// Every edge value of `a` and `b` is within `tolerance`, and both are real numbers.
    public static func matches(_ a: TileRect, _ b: TileRect, tolerance: Double = TileReadBack.tolerance) -> Bool {
        let pairs = [(a.x, b.x), (a.y, b.y), (a.width, b.width), (a.height, b.height)]
        for (left, right) in pairs {
            guard left.isFinite, right.isFinite, abs(left - right) <= tolerance else { return false }
        }
        return true
    }

    /// A write landed when the frame read back afterward matches the one asked for. An unreadable frame did not.
    public static func landed(intended: TileRect, actual: TileRect?) -> Bool {
        guard let actual else { return false }
        return matches(intended, actual)
    }
}

/// The frames the driver asked for lately, so the layout can tell its own move notifications from a person
/// dragging a window. A write is remembered for `lifetime` seconds and may match several notifications.
public struct TileSelfWrites: Equatable, Sendable {
    public static let lifetime = 1.5

    private struct Entry: Equatable, Sendable {
        var frame: TileRect
        var at: Double
    }

    private var entries: [TileWindowID: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// Remembers `frames` as written at `time`. A newer write for a window replaces its older one.
    public mutating func record(_ frames: [TileWindowID: TileRect], at time: Double) {
        for (window, frame) in frames { entries[window] = Entry(frame: frame, at: time) }
    }

    /// True when `window` was written lately and `observed` is the frame that write asked for.
    public func isOwnEcho(_ window: TileWindowID, observed: TileRect, at time: Double) -> Bool {
        guard let entry = entries[window], time - entry.at <= Self.lifetime else { return false }
        return TileReadBack.matches(entry.frame, observed)
    }

    /// Forgets writes older than the lifetime.
    public mutating func prune(now: Double) {
        entries = entries.filter { now - $0.value.at <= Self.lifetime }
    }
}
