import CoreGraphics
import Foundation

/// The pointer's path while the pointing keys are held, kept as strokes for drawing and targeting.
/// Pure and bounded. Near-duplicate samples are dropped, a pause of `pauseSplit` seconds starts a new
/// stroke (so separate shapes stay separate), and smoothing keeps corners sharp.
/// The arithmetic lives in `PointingInkTrailBox`.
public struct PointingInkTrail: Equatable, Sendable {
    public static let minSpacing = PointingInkTrailBox.minSpacing
    public static let pauseSplit = PointingInkTrailBox.pauseSplit
    public static let maxStrokes = PointingInkTrailBox.maxStrokes
    public static let maxPointsPerStroke = PointingInkTrailBox.maxPointsPerStroke
    /// A turn sharper than this many degrees is a corner and is never rounded off.
    public static let cornerDegrees = PointingInkTrailBox.cornerDegrees

    public enum Step: Equatable, Sendable { case dropped, began, extended }

    private var box = PointingInkTrailBox()

    /// Accepted raw points, oldest stroke first.
    public var strokes: [[CGPoint]] {
        box.strokes.map { stroke in stroke.map { CGPoint(x: $0.x, y: $0.y) } }
    }

    public var droppedPoints: Int { box.droppedPoints }

    public init() {}

    @discardableResult
    public mutating func add(_ point: CGPoint, at time: Double) -> Step {
        switch box.add(PointingInkTrailBox.Point(x: Double(point.x), y: Double(point.y)), at: time) {
        case .dropped: .dropped
        case .began: .began
        case .extended: .extended
        }
    }

    /// The next accepted point starts a new stroke.
    public mutating func endStroke() { box.endStroke() }

    public var isDrawing: Bool { box.isDrawing }

    public mutating func reset() { self = PointingInkTrail() }

    /// The strokes to draw: corner-preserving smoothing of each.
    public var smoothed: [[CGPoint]] { strokes.map(Self.smooth) }

    /// Chaikin corner cutting on each run between corners, so curves become smooth and real corners
    /// (and both endpoints) stay exactly where the pointer put them.
    public static func smooth(_ points: [CGPoint]) -> [CGPoint] {
        PointingInkTrailBox.smooth(points.map { PointingInkTrailBox.Point(x: Double($0.x), y: Double($0.y)) })
            .map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Degrees the path turns at `b` (0 is straight on, 180 is a reversal).
    static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        PointingInkTrailBox.turn(PointingInkTrailBox.Point(x: Double(a.x), y: Double(a.y)),
                                 PointingInkTrailBox.Point(x: Double(b.x), y: Double(b.y)),
                                 PointingInkTrailBox.Point(x: Double(c.x), y: Double(c.y)))
    }
}
