import Foundation

/// Dash-phase motion for a flow along a tube or a path.
///
/// Phase 4 asks for that motion to be driven only by presentation time, the same
/// clock as `ExplanationPresentation.sample(at:)`. The caller passes the time and
/// whether Reduce Motion is on. This type does not read system settings and does not draw.
///
/// The dash is the canvas stroke pattern, 6 on and 5 off. One full pattern travels
/// per second of presentation time. The arrowhead uses the canvas head: 0.45 radians
/// off the reverse tangent, with a length of `min(segment, max(8, min(18, lineWidth * 3)))`.
/// Reduce Motion drops the travelling dash and leaves those arrowheads in place.
public enum ExplanationFlowGeometry {
    /// Canvas dash length in `ExplanationCanvasPainter`.
    public static let dashOn = 6.0
    /// Canvas gap length in `ExplanationCanvasPainter`.
    public static let dashOff = 5.0
    public static let dashPeriod = dashOn + dashOff
    /// Arrow wing angle in `ExplanationCanvasPainter`, in radians.
    public static let arrowAngle = 0.45
    /// Shortest canvas arrow head, in path units.
    public static let minimumArrowLength = 8.0
    /// Longest canvas arrow head, in path units.
    public static let maximumArrowLength = 18.0

    /// A path is the centerline alone. A tube keeps the same centerline and adds a radius.
    public enum Centerline: Equatable, Sendable {
        case path
        case tube(radius: Double)
    }

    public struct Arrowhead: Equatable, Sendable {
        public var tip: ExplanationVector3
        public var left: ExplanationVector3
        public var right: ExplanationVector3
        /// Unit direction of travel. Reverse flow already points backward.
        public var tangent: ExplanationVector3

        public init(tip: ExplanationVector3, left: ExplanationVector3, right: ExplanationVector3,
                    tangent: ExplanationVector3) {
            self.tip = tip
            self.left = left
            self.right = right
            self.tangent = tangent
        }
    }

    public struct Sample: Equatable, Sendable {
        /// Offset of the 6-on, 5-off pattern, in `[0, dashPeriod)`. Zero when the dash is held still.
        public var dashPhase: Double
        /// Empty while the dash travels. Filled with a fixed set under Reduce Motion.
        public var arrowheads: [Arrowhead]
        public var reduced: Bool
        /// Set only when the centerline is a tube with a finite radius above zero.
        public var tubeRadius: Double?

        public init(dashPhase: Double, arrowheads: [Arrowhead], reduced: Bool, tubeRadius: Double?) {
            self.dashPhase = dashPhase
            self.arrowheads = arrowheads
            self.reduced = reduced
            self.tubeRadius = tubeRadius
        }
    }

    /// `presentationTime` is media time in seconds. A time that is not finite, or is below zero,
    /// does not move the pattern. `arrowCount` is clamped to `1...ExplanationModelLimits.markersPerFlow`.
    public static func sample(
        points: [ExplanationVector3],
        at presentationTime: Double,
        reduceMotion: Bool,
        direction: ExplanationFlow.Direction = .forward,
        centerline: Centerline = .path,
        lineWidth: Double = 2,
        arrowCount: Int = 4
    ) -> Sample {
        let drawn = canDraw(points)
        let phase = reduceMotion || !drawn ? 0 : dashPhase(at: presentationTime, direction: direction)
        let heads = reduceMotion && drawn
            ? arrowheads(points: points, direction: direction, lineWidth: lineWidth, count: arrowCount)
            : []
        return Sample(dashPhase: phase, arrowheads: heads, reduced: reduceMotion, tubeRadius: tubeRadius(centerline))
    }

    private static func canDraw(_ points: [ExplanationVector3]) -> Bool {
        guard points.count >= 2 else { return false }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return false }
        return ExplanationFlowMath.length(of: points) > 1e-9
    }

    private static func dashPhase(at time: Double, direction: ExplanationFlow.Direction) -> Double {
        guard time.isFinite, time > 0 else { return 0 }
        let travelled = time * dashPeriod * direction.sign
        return ExplanationV3.positiveModulo(travelled, dashPeriod)
    }

    private static func tubeRadius(_ centerline: Centerline) -> Double? {
        guard case .tube(let radius) = centerline, radius.isFinite, radius > 0 else { return nil }
        return radius
    }

    private static func arrowheads(
        points: [ExplanationVector3],
        direction: ExplanationFlow.Direction,
        lineWidth: Double,
        count requested: Int
    ) -> [Arrowhead] {
        let total = ExplanationFlowMath.length(of: points)
        guard total > 1e-9 else { return [] }
        let count = min(max(requested, 1), ExplanationModelLimits.markersPerFlow)
        var result: [Arrowhead] = []
        for index in 0..<count {
            let distance = ExplanationV3.positiveModulo(total * Double(index) / Double(count), total)
            guard let sampled = ExplanationFlowMath.sample(points, at: distance) else { continue }
            let tangent = ExplanationV3.scale(sampled.tangent, direction.sign)
            guard let head = arrowhead(tip: sampled.position, tangent: tangent,
                                       segment: segmentLength(points, at: distance), lineWidth: lineWidth) else { continue }
            result.append(head)
        }
        return result
    }

    /// Length of the polyline segment that contains `distance`, matching `ExplanationFlowMath.sample`.
    private static func segmentLength(_ points: [ExplanationVector3], at distance: Double) -> Double {
        var remaining = max(0, distance)
        var last = 0.0
        for index in 0..<(points.count - 1) {
            let length = ExplanationV3.length(ExplanationV3.sub(points[index + 1], points[index]))
            guard length > 1e-12 else { continue }
            last = length
            if remaining <= length { return length }
            remaining -= length
        }
        return last
    }

    private static func arrowhead(
        tip: ExplanationVector3, tangent: ExplanationVector3, segment: Double, lineWidth: Double
    ) -> Arrowhead? {
        guard ExplanationV3.length(tangent) > 0, segment > 0 else { return nil }
        let width = lineWidth.isFinite && lineWidth >= 0 ? lineWidth : 2
        let scaled = min(maximumArrowLength, max(width * 3, 0))
        let length = min(segment, max(minimumArrowLength, scaled))
        guard length > 0, length.isFinite else { return nil }
        let side = perpendicular(to: tangent)
        let back = ExplanationV3.scale(tangent, -cos(arrowAngle))
        let flank = sin(arrowAngle)
        let left = ExplanationV3.add(back, ExplanationV3.scale(side, flank))
        let right = ExplanationV3.add(back, ExplanationV3.scale(side, -flank))
        return Arrowhead(
            tip: tip,
            left: ExplanationV3.add(tip, ExplanationV3.scale(left, length)),
            right: ExplanationV3.add(tip, ExplanationV3.scale(right, length)),
            tangent: tangent)
    }

    /// World up, then world X when the path runs along Y, so a vertical tube still has wings.
    private static func perpendicular(to tangent: ExplanationVector3) -> ExplanationVector3 {
        let up = ExplanationVector3(x: 0, y: 1, z: 0)
        var side = ExplanationV3.cross(tangent, up)
        if ExplanationV3.length(side) <= 1e-8 {
            side = ExplanationV3.cross(tangent, ExplanationVector3(x: 1, y: 0, z: 0))
        }
        return ExplanationV3.normalized(side)
    }
}
