// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): Liveness/LandmarkGeometry.swift, FaceAligner.swift.
import CoreGraphics

/// Pure landmark geometry for aligning a face crop. Points are plain `CGPoint` values, so nothing here
/// touches Vision, an image or a camera. Callers pass points with the origin at the top left, y down.
/// The arithmetic lives in `LandmarkMathBox`.
public enum LandmarkMath {
    /// Side of the aligned square crop, in pixels.
    public static let templateSize = LandmarkMathBox.templateSize

    /// Where the five alignment points sit in the aligned crop: left eye, right eye, nose, left mouth corner,
    /// right mouth corner. "Left" and "right" are on screen, not anatomical.
    public static let template: [CGPoint] = LandmarkMathBox.template.map(cgPoint)

    /// The eye pair of `template`, used when only the eyes are known.
    public static let eyeTemplate: [CGPoint] = LandmarkMathBox.eyeTemplate.map(cgPoint)

    /// Mean of the points, or nil when there are none or any coordinate is not finite.
    public static func centroid(_ points: [CGPoint]) -> CGPoint? {
        LandmarkMathBox.centroid(points.map(boxPoint)).map(cgPoint)
    }

    /// The pupil point when there is one (a precise point), else the centre of the eye outline.
    public static func eyeCenter(pupil: [CGPoint], eye: [CGPoint]) -> CGPoint? {
        LandmarkMathBox.eyeCenter(pupil: pupil.map(boxPoint), eye: eye.map(boxPoint)).map(cgPoint)
    }

    /// Vision reports pixel points with the origin at the bottom left. This moves them to the top left.
    /// Applying it twice gives the points back.
    public static func flipVertical(_ points: [CGPoint], imageHeight: CGFloat) -> [CGPoint] {
        LandmarkMathBox.flipVertical(points.map(boxPoint), imageHeight: Double(imageHeight)).map(cgPoint)
    }

    /// The two eyes in screen order. Vision's left and right labels are anatomical, so the x position decides.
    public static func twoPoints(eyeA: CGPoint, eyeB: CGPoint) -> [CGPoint] {
        LandmarkMathBox.twoPoints(eyeA: boxPoint(eyeA), eyeB: boxPoint(eyeB)).map(cgPoint)
    }

    /// Eyes, nose and mouth corners in template order, or nil when the lips have no points.
    public static func fivePoints(eyeA: CGPoint, eyeB: CGPoint, nose: CGPoint, lips: [CGPoint]) -> [CGPoint]? {
        LandmarkMathBox.fivePoints(eyeA: boxPoint(eyeA), eyeB: boxPoint(eyeB), nose: boxPoint(nose),
                                    lips: lips.map(boxPoint)).map { $0.map(cgPoint) }
    }

    /// Middle value of the list; the mean of the middle two for an even count; 0 for an empty list.
    public static func median(_ values: [CGFloat]) -> CGFloat {
        CGFloat(LandmarkMathBox.median(values.map { Double($0) }))
    }

    /// Least-squares rotation, uniform scale and shift taking `source` onto `destination`, in closed form
    /// (2D Procrustes with complex numbers, no SVD). Nil for fewer than two pairs, mismatched counts, source points
    /// that all coincide, or any value that is not finite.
    public static func similarityTransform(from source: [CGPoint], to destination: [CGPoint]) -> CGAffineTransform? {
        guard let solved = LandmarkMathBox.similarityTransform(from: source.map(boxPoint), to: destination.map(boxPoint)) else {
            return nil
        }
        return CGAffineTransform(a: CGFloat(solved.a), b: CGFloat(solved.b), c: CGFloat(solved.c),
                                  d: CGFloat(solved.d), tx: CGFloat(solved.tx), ty: CGFloat(solved.ty))
    }

    private static func boxPoint(_ point: CGPoint) -> LandmarkMathBox.Point {
        LandmarkMathBox.Point(x: Double(point.x), y: Double(point.y))
    }

    private static func cgPoint(_ point: LandmarkMathBox.Point) -> CGPoint {
        CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }
}
