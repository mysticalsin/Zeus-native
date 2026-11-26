// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): Liveness/LandmarkGeometry.swift.
import Foundation

/// Landmark geometry as `Double`s. Points use a top-left origin, y down. This type does not
/// read a camera, an image, or a clock.
public enum LandmarkMathBox {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Closed-form similarity: `x' = a x + c y + tx`, `y' = b x + d y + ty`.
    public struct Similarity: Equatable, Sendable {
        public var a: Double
        public var b: Double
        public var c: Double
        public var d: Double
        public var tx: Double
        public var ty: Double

        public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.tx = tx
            self.ty = ty
        }
    }

    /// Side of the aligned square crop, in pixels.
    public static let templateSize = 112

    /// Left eye, right eye, nose, left mouth corner, right mouth corner. Left and right are on screen.
    public static let template: [Point] = [
        Point(x: 38.2946, y: 51.6963),
        Point(x: 73.5318, y: 51.5014),
        Point(x: 56.0252, y: 71.7366),
        Point(x: 41.5493, y: 92.3655),
        Point(x: 70.7299, y: 92.2041),
    ]

    /// The eye pair of `template`, used when only the eyes are known.
    public static let eyeTemplate: [Point] = Array(template.prefix(2))

    /// Mean of the points, or nil when there are none or any coordinate is not finite.
    public static func centroid(_ points: [Point]) -> Point? {
        guard !points.isEmpty, points.allSatisfy(isFinite) else { return nil }
        let count = Double(points.count)
        let sum = points.reduce(Point(x: 0, y: 0)) { Point(x: $0.x + $1.x, y: $0.y + $1.y) }
        return Point(x: sum.x / count, y: sum.y / count)
    }

    /// The pupil point when there is one, else the centre of the eye outline.
    public static func eyeCenter(pupil: [Point], eye: [Point]) -> Point? {
        centroid(pupil) ?? centroid(eye)
    }

    /// Moves bottom-left pixel points to a top-left origin. Applying it twice restores them.
    public static func flipVertical(_ points: [Point], imageHeight: Double) -> [Point] {
        points.map { Point(x: $0.x, y: imageHeight - $0.y) }
    }

    /// The two eyes in screen order. The x position decides, not an anatomical label.
    public static func twoPoints(eyeA: Point, eyeB: Point) -> [Point] {
        eyeA.x <= eyeB.x ? [eyeA, eyeB] : [eyeB, eyeA]
    }

    /// Eyes, nose and mouth corners in template order, or nil when the lips have no points.
    public static func fivePoints(eyeA: Point, eyeB: Point, nose: Point, lips: [Point]) -> [Point]? {
        guard let leftMouth = lips.min(by: { $0.x < $1.x }),
              let rightMouth = lips.max(by: { $0.x < $1.x }) else { return nil }
        let eyes = twoPoints(eyeA: eyeA, eyeB: eyeB)
        return [eyes[0], eyes[1], nose, leftMouth, rightMouth]
    }

    /// Middle value; the mean of the middle two when the count is even; 0 when the list is empty.
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Least-squares rotation, uniform scale and shift. Nil for fewer than two pairs, a count
    /// mismatch, source points that all coincide, or any value that is not finite.
    public static func similarityTransform(from source: [Point], to destination: [Point]) -> Similarity? {
        guard source.count == destination.count, source.count >= 2,
              source.allSatisfy(isFinite), destination.allSatisfy(isFinite),
              let sourceMean = centroid(source), let destinationMean = centroid(destination) else { return nil }

        var real = 0.0
        var imaginary = 0.0
        var denominator = 0.0
        for (s, d) in zip(source, destination) {
            let p = Point(x: s.x - sourceMean.x, y: s.y - sourceMean.y)
            let q = Point(x: d.x - destinationMean.x, y: d.y - destinationMean.y)
            real += q.x * p.x + q.y * p.y
            imaginary += q.y * p.x - q.x * p.y
            denominator += p.x * p.x + p.y * p.y
        }
        guard denominator > 0, denominator.isFinite else { return nil }

        let cosScale = real / denominator
        let sinScale = imaginary / denominator
        let tx = destinationMean.x - (cosScale * sourceMean.x - sinScale * sourceMean.y)
        let ty = destinationMean.y - (sinScale * sourceMean.x + cosScale * sourceMean.y)
        guard [cosScale, sinScale, tx, ty].allSatisfy(\.isFinite) else { return nil }
        return Similarity(a: cosScale, b: sinScale, c: -sinScale, d: cosScale, tx: tx, ty: ty)
    }

    private static func isFinite(_ point: Point) -> Bool { point.x.isFinite && point.y.isFinite }
}
