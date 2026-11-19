// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceDetector.swift, FaceRecognitionPipeline.swift.
import CoreGraphics

/// Picks the person at the camera from the faces in one frame, and does the rectangle math for cropping.
/// Boxes are Vision's normalized rectangles (0 to 1, origin at the bottom left). Selection returns an index
/// into the input, so the caller keeps its own observation and never copies one.
public enum FaceSelection {
    /// A face narrower than this fraction of the frame is a bystander, not a candidate.
    public static let minimumWidth: CGFloat = 0.18
    /// The most a face centre may drift between frames and still count as the same person.
    public static let continuityTolerance: CGFloat = 0.3
    /// Fraction of the face box added on each side before cropping.
    public static let cropPadding: CGFloat = 0.2

    /// The face to analyse: wide enough to be a candidate, then the one closest to the previous frame's face when
    /// that is near enough, else the largest. Continuity stops two similar faces from swapping every frame.
    public static func select(in boxes: [CGRect], preferNear previous: CGRect?) -> Int? {
        let candidates = boxes.indices.filter { isUsable(boxes[$0]) && boxes[$0].width >= minimumWidth }
        guard !candidates.isEmpty else { return nil }

        if let previous, isUsable(previous) {
            let anchor = CGPoint(x: previous.midX, y: previous.midY)
            var nearest = candidates[0]
            for index in candidates.dropFirst() where distance(boxes[index], anchor) < distance(boxes[nearest], anchor) {
                nearest = index
            }
            if distance(boxes[nearest], anchor) < continuityTolerance { return nearest }
        }
        return largest(among: candidates, in: boxes)
    }

    /// The largest face by area with no width floor, so enrollment can tell "too far away" from "nobody there".
    public static func largest(in boxes: [CGRect]) -> Int? {
        largest(among: boxes.indices.filter { isUsable(boxes[$0]) }, in: boxes)
    }

    /// Vision's normalized rectangle (origin bottom left) as a pixel rectangle with the origin at the top left.
    public static func imageRect(fromNormalized rect: CGRect, imageSize: CGSize) -> CGRect {
        let width = rect.width * imageSize.width
        let height = rect.height * imageSize.height
        return CGRect(x: rect.origin.x * imageSize.width,
                      y: (1 - rect.origin.y) * imageSize.height - height,
                      width: width, height: height)
    }

    /// The face box grown by `padding` on each side and clipped to the image, on whole pixels. Nil when nothing is left.
    public static func paddedCrop(_ box: CGRect, imageSize: CGSize, padding: CGFloat = cropPadding) -> CGRect? {
        guard isUsable(box), imageSize.width.isFinite, imageSize.height.isFinite else { return nil }
        let bounds = CGRect(origin: .zero, size: imageSize)
        let padded = box.insetBy(dx: -box.width * padding, dy: -box.height * padding).integral.intersection(bounds)
        guard !padded.isNull, padded.width > 0, padded.height > 0 else { return nil }
        return padded
    }

    private static func largest(among indices: [Int], in boxes: [CGRect]) -> Int? {
        guard var best = indices.first else { return nil }
        for index in indices.dropFirst() where area(boxes[index]) > area(boxes[best]) { best = index }
        return best
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    private static func distance(_ box: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(box.midX - point.x, box.midY - point.y)
    }
}
