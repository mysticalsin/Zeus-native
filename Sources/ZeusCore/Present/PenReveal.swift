import Foundation

/// One point of a hand-drawn pen stroke, in the caller's coordinate space.
public struct PenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// How much of a pen stroke is visible at one moment of a beat.
///
/// The stroke follows arc length, so a long segment takes more of the beat
/// than a short one. Progress 0 draws nothing. Progress 1 draws every point.
/// A later progress stays on the last point. Reduced motion draws the whole
/// stroke at once, including at the start of the beat.
///
/// The step is dropped when the screen has changed, when progress is negative
/// or not finite, when a coordinate is not finite, when the stroke has no
/// length, or when it has fewer than two points or more than 24. Nothing here
/// draws, reads a clock, or opens a connection. The points are not applied to
/// a talk draw.
public enum PenReveal {
    public static let maxPoints = 24
    private static let snap = 0.000_000_001

    public static func stroke(
        _ points: [PenPoint],
        progress: Double,
        reduceMotion: Bool,
        screen: Int,
        currentScreen: Int
    ) -> [PenPoint]? {
        guard usable(points), screen == currentScreen, progress.isFinite, progress >= 0 else { return nil }
        if reduceMotion || progress >= 1 { return points }
        return along(points, progress: progress)
    }

    private static func usable(_ points: [PenPoint]) -> Bool {
        guard (2...maxPoints).contains(points.count) else { return false }
        for point in points where !point.x.isFinite || !point.y.isFinite { return false }
        return length(points) > snap
    }

    private static func along(_ points: [PenPoint], progress: Double) -> [PenPoint] {
        if progress <= 0 { return [] }
        var remaining = length(points) * progress
        var drawn = [points[0]]
        for index in 1..<points.count {
            if remaining <= snap { break }
            let start = points[index - 1]
            let end = points[index]
            let span = distance(start, end)
            if span <= snap { continue }
            if remaining + snap >= span {
                remaining -= span
                if drawn[drawn.count - 1] != end { drawn.append(end) }
            } else {
                let portion = remaining / span
                drawn.append(PenPoint(
                    x: start.x + (end.x - start.x) * portion,
                    y: start.y + (end.y - start.y) * portion))
                break
            }
        }
        return drawn
    }

    private static func length(_ points: [PenPoint]) -> Double {
        var total = 0.0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return total
    }

    private static func distance(_ start: PenPoint, _ end: PenPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
