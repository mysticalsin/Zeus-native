// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): Liveness/LandmarkGeometry.swift, FaceAligner.swift.
import CoreGraphics

/// Pure landmark geometry for aligning a face crop. Points are plain `CGPoint` values, so nothing here
/// touches Vision, an image or a camera. Callers pass points with the origin at the top left, y down.
public enum LandmarkMath {
    /// Side of the aligned square crop, in pixels.
    public static let templateSize = 112

    /// Where the five alignment points sit in the aligned crop: left eye, right eye, nose, left mouth corner,
    /// right mouth corner. "Left" and "right" are on screen, not anatomical.
    public static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    /// The eye pair of `template`, used when only the eyes are known.
    public static let eyeTemplate: [CGPoint] = Array(template.prefix(2))

    /// Mean of the points, or nil when there are none or any coordinate is not finite.
    public static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty, points.allSatisfy(isFinite) else { return nil }
        let count = CGFloat(points.count)
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }

    /// The pupil point when there is one (a precise point), else the centre of the eye outline.
    public static func eyeCenter(pupil: [CGPoint], eye: [CGPoint]) -> CGPoint? {
        centroid(pupil) ?? centroid(eye)
    }

    /// Vision reports pixel points with the origin at the bottom left. This moves them to the top left.
    /// Applying it twice gives the points back.
    public static func flipVertical(_ points: [CGPoint], imageHeight: CGFloat) -> [CGPoint] {
        points.map { CGPoint(x: $0.x, y: imageHeight - $0.y) }
    }

    /// The two eyes in screen order. Vision's left and right labels are anatomical, so the x position decides.
    public static func twoPoints(eyeA: CGPoint, eyeB: CGPoint) -> [CGPoint] {
        eyeA.x <= eyeB.x ? [eyeA, eyeB] : [eyeB, eyeA]
    }

    /// Eyes, nose and mouth corners in template order, or nil when the lips have no points.
    public static func fivePoints(eyeA: CGPoint, eyeB: CGPoint, nose: CGPoint, lips: [CGPoint]) -> [CGPoint]? {
        guard let leftMouth = lips.min(by: { $0.x < $1.x }), let rightMouth = lips.max(by: { $0.x < $1.x }) else { return nil }
        let eyes = twoPoints(eyeA: eyeA, eyeB: eyeB)
        return [eyes[0], eyes[1], nose, leftMouth, rightMouth]
    }

    /// Middle value of the list; the mean of the middle two for an even count; 0 for an empty list.
    public static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Least-squares rotation, uniform scale and shift taking `source` onto `destination`, in closed form
    /// (2D Procrustes with complex numbers, no SVD). Nil for fewer than two pairs, mismatched counts, source points
    /// that all coincide, or any value that is not finite.
    public static func similarityTransform(from source: [CGPoint], to destination: [CGPoint]) -> CGAffineTransform? {
        guard source.count == destination.count, source.count >= 2,
              source.allSatisfy(isFinite), destination.allSatisfy(isFinite),
              let sourceMean = centroid(source), let destinationMean = centroid(destination) else { return nil }

        var real: CGFloat = 0
        var imaginary: CGFloat = 0
        var denominator: CGFloat = 0
        for (s, d) in zip(source, destination) {
            let p = CGPoint(x: s.x - sourceMean.x, y: s.y - sourceMean.y)
            let q = CGPoint(x: d.x - destinationMean.x, y: d.y - destinationMean.y)
            // q * conj(p) = (qx + i qy)(px - i py)
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
        return CGAffineTransform(a: cosScale, b: sinScale, c: -sinScale, d: cosScale, tx: tx, ty: ty)
    }

    private static func isFinite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
}
