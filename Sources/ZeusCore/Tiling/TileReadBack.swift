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
