import Foundation

/// Pointer strokes as `Double` points. Near-duplicate samples are dropped, a pause starts a new
/// stroke, and a sharp corner is kept. This type does not read a pointer, a screen, or a clock.
public struct PointingInkTrailBox: Equatable, Sendable {
    public static let minSpacing = 2.5
    public static let pauseSplit = 0.6
    public static let maxStrokes = 16
    public static let maxPointsPerStroke = 512
    /// A turn sharper than this many degrees is a corner and is never rounded off.
    public static let cornerDegrees = 55.0

    public enum Step: Equatable, Sendable { case dropped, began, extended }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Accepted raw points, oldest stroke first.
    public private(set) var strokes: [[Point]] = []
    public private(set) var droppedPoints = 0
    private var open = false
    private var lastTime: Double?

    public init() {}

    @discardableResult
    public mutating func add(_ point: Point, at time: Double) -> Step {
        guard point.x.isFinite, point.y.isFinite, time.isFinite else { droppedPoints += 1; return .dropped }
        if open, var current = strokes.popLast() {
            defer { strokes.append(current) }
            if let last = current.last, Self.distance(point, last) < Self.minSpacing {
                droppedPoints += 1
                return .dropped
            }
            if let lastTime, time - lastTime >= Self.pauseSplit {
                open = false
            } else {
                current.append(point)
                if current.count > Self.maxPointsPerStroke { current.removeFirst(); droppedPoints += 1 }
                lastTime = time
                return .extended
            }
        }
        if strokes.count >= Self.maxStrokes { strokes.removeFirst(); droppedPoints += 1 }
        strokes.append([point])
        open = true
        lastTime = time
        return .began
    }

    /// The next accepted point starts a new stroke.
    public mutating func endStroke() { open = false }

    public var isDrawing: Bool { open }

    public mutating func reset() { self = PointingInkTrailBox() }

    /// The strokes to draw: corner-preserving smoothing of each.
    public var smoothed: [[Point]] { strokes.map(Self.smooth) }

    /// Chaikin corner cutting on each run between corners, so curves become smooth and real corners
    /// (and both endpoints) stay exactly where the pointer put them.
    public static func smooth(_ points: [Point]) -> [Point] {
        guard points.count >= 3 else { return points }
        var corners: [Int] = [0]
        for index in 1..<(points.count - 1) where turn(points[index - 1], points[index], points[index + 1]) > cornerDegrees {
            corners.append(index)
        }
        corners.append(points.count - 1)
        var out: [Point] = []
        for pair in zip(corners, corners.dropFirst()) {
            var run = Array(points[pair.0...pair.1])
            run = cut(cut(run))
            out.append(contentsOf: out.isEmpty ? run : Array(run.dropFirst()))
        }
        return out
    }

    private static func cut(_ run: [Point]) -> [Point] {
        guard run.count >= 3, let first = run.first, let last = run.last else { return run }
        var out = [first]
        for index in 0..<(run.count - 1) {
            let a = run[index], b = run[index + 1]
            if index != 0 { out.append(Point(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y)) }
            if index != run.count - 2 { out.append(Point(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y)) }
        }
        out.append(last)
        return out
    }

    /// Degrees the path turns at `b` (0 is straight on, 180 is a reversal).
    public static func turn(_ a: Point, _ b: Point, _ c: Point) -> Double {
        let ux = b.x - a.x, uy = b.y - a.y, vx = c.x - b.x, vy = c.y - b.y
        guard Self.distance(Point(x: ux, y: uy), Point(x: 0, y: 0)) > 0,
              Self.distance(Point(x: vx, y: vy), Point(x: 0, y: 0)) > 0 else { return 0 }
        return abs(atan2(ux * vy - uy * vx, ux * vx + uy * vy)) * 180 / .pi
    }

    private static func distance(_ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
