import CoreGraphics
import Foundation

/// One raw sample. Kept after the ink has faded.
public struct TrailSample: Equatable, Sendable {
    public var point: CGPoint
    public var time: Double

    public init(point: CGPoint, time: Double) {
        self.point = point
        self.time = time
    }
}

/// Gesture ink. Capture, dwell, and the fade are separate from the companion flight.
public struct SpatialTrail: Equatable, Sendable {
    public static let activation: Double = 8
    public static let spacing: Double = 1.5
    public static let dwellRadius: Double = 12
    public static let dwellQualification: Double = 0.350
    public static let strokeWidth: Double = 8
    public static let fadeSeconds: Double = 1
    public static let parentOpacity: Double = 0.55
    public static let maxSubdivisions: Int = 48

    public private(set) var raw: [TrailSample] = []
    public private(set) var kept: [TrailSample] = []
    public private(set) var dwell: CGPoint?
    public private(set) var inkHidden = false
    private var origin: CGPoint?
    private var active = false
    private var dwellAnchor: TrailSample?

    public init() {}

    public mutating func add(point: CGPoint, at time: Double) {
        let sample = TrailSample(point: point, time: time)
        raw.append(sample)
        if origin == nil { origin = point }
        guard let origin else { return }
        if !active {
            guard hypot(point.x - origin.x, point.y - origin.y) >= Self.activation else { return }
            active = true
        }
        if let last = kept.last, hypot(point.x - last.point.x, point.y - last.point.y) < Self.spacing { 
            noteDwell(sample)
            return
        }
        kept.append(sample)
        dwellAnchor = sample
    }

    /// Age alpha for one kept point, already multiplied by the parent opacity.
    public func alpha(of sample: TrailSample, at time: Double) -> Double {
        guard !inkHidden else { return 0 }
        let age = max(0, time - sample.time)
        return Self.parentOpacity * max(0, 1 - age / Self.fadeSeconds)
    }

    /// Stop watching. Ink disappears. Raw points and the dwell anchor stay.
    public mutating func hideInk() { inkHidden = true }

    /// Centripetal Catmull-Rom through the kept points. At most 48 generated points.
    public func smooth() -> [CGPoint] {
        let points = kept.map(\.point)
        guard points.count >= 2 else { return points }
        let segments = points.count - 1
        let perSegment = max(1, Self.maxSubdivisions / segments)
        var output: [CGPoint] = [points[0]]
        for index in 0..<segments {
            let p0 = index == 0 ? extrapolate(points[0], points[1]) : points[index - 1]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : extrapolate(points[index + 1], points[index])
            for step in 1...perSegment {
                let t = Double(step) / Double(perSegment)
                output.append(centripetal(p0, p1, p2, p3, t))
                if output.count >= Self.maxSubdivisions { return output }
            }
        }
        return output
    }

    private mutating func noteDwell(_ sample: TrailSample) {
        guard let anchor = dwellAnchor else { dwellAnchor = sample; return }
        guard hypot(sample.point.x - anchor.point.x, sample.point.y - anchor.point.y) <= Self.dwellRadius else {
            dwellAnchor = sample
            return
        }
        if sample.time - anchor.time >= Self.dwellQualification { dwell = anchor.point }
    }

    private func extrapolate(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x * 2 - b.x, y: a.y * 2 - b.y)
    }

    /// Centripetal (alpha 0.5) Catmull-Rom between p1 and p2.
    private func centripetal(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        func knot(_ a: CGPoint, _ b: CGPoint, _ previous: Double) -> Double {
            let distance = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            return previous + distance.squareRoot()
        }
        let t0 = 0.0
        let t1 = knot(p0, p1, t0)
        let t2 = knot(p1, p2, t1)
        let t3 = knot(p2, p3, t2)
        let u = t1 + (t2 - t1) * t
        let a1 = lerp(p0, p1, (u - t0) / (t1 - t0))
        let a2 = lerp(p1, p2, (u - t1) / (t2 - t1))
        let a3 = lerp(p2, p3, (u - t2) / (t3 - t2))
        let b1 = lerp(a1, a2, (u - t0) / (t2 - t0))
        let b2 = lerp(a2, a3, (u - t1) / (t3 - t1))
        return lerp(b1, b2, (u - t1) / (t2 - t1))
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
