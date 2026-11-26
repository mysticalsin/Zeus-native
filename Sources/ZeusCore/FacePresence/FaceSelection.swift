// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceDetector.swift, FaceRecognitionPipeline.swift.
import CoreGraphics

/// Picks the person at the camera from the faces in one frame, and does the rectangle math for cropping.
/// Boxes are Vision's normalized rectangles (0 to 1, origin at the bottom left). Selection returns an index
/// into the input, so the caller keeps its own observation and never copies one.
/// The arithmetic lives in `FaceSelectionBox`.
public enum FaceSelection {
    /// A face narrower than this fraction of the frame is a bystander, not a candidate.
    public static let minimumWidth: CGFloat = CGFloat(FaceSelectionBox.minimumWidth)
    /// The most a face centre may drift between frames and still count as the same person.
    public static let continuityTolerance: CGFloat = CGFloat(FaceSelectionBox.continuityTolerance)
    /// Fraction of the face box added on each side before cropping.
    public static let cropPadding: CGFloat = CGFloat(FaceSelectionBox.cropPadding)

    /// The face to analyse: wide enough to be a candidate, then the one closest to the previous frame's face when
    /// that is near enough, else the largest. Continuity stops two similar faces from swapping every frame.
    public static func select(in boxes: [CGRect], preferNear previous: CGRect?) -> Int? {
        FaceSelectionBox.select(in: boxes.map(boxRect), preferNear: previous.map(boxRect))
    }

    /// The largest face by area with no width floor, so enrollment can tell "too far away" from "nobody there".
    public static func largest(in boxes: [CGRect]) -> Int? {
        FaceSelectionBox.largest(in: boxes.map(boxRect))
    }

    /// Vision's normalized rectangle (origin bottom left) as a pixel rectangle with the origin at the top left.
    public static func imageRect(fromNormalized rect: CGRect, imageSize: CGSize) -> CGRect {
        cgRect(FaceSelectionBox.imageRect(fromNormalized: boxRect(rect), imageSize: boxSize(imageSize)))
    }

    /// The face box grown by `padding` on each side and clipped to the image, on whole pixels. Nil when nothing is left.
    public static func paddedCrop(_ box: CGRect, imageSize: CGSize, padding: CGFloat = cropPadding) -> CGRect? {
        FaceSelectionBox.paddedCrop(boxRect(box), imageSize: boxSize(imageSize), padding: Double(padding)).map(cgRect)
    }

    private static func boxRect(_ rect: CGRect) -> FaceSelectionBox.Rect {
        FaceSelectionBox.Rect(x: Double(rect.origin.x), y: Double(rect.origin.y),
                              width: Double(rect.size.width), height: Double(rect.size.height))
    }

    private static func boxSize(_ size: CGSize) -> FaceSelectionBox.Size {
        FaceSelectionBox.Size(width: Double(size.width), height: Double(size.height))
    }

    private static func cgRect(_ rect: FaceSelectionBox.Rect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
