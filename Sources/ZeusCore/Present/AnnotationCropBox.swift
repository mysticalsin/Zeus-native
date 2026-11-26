#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// Overlap, mark size, label, and JPEG quality for a marked crop.
/// `AnnotationCrop` keeps ImageIO. This type takes the stored origin and size.
/// Linux Foundation provides the rectangle type, so the overlap is the same intersection the parent used.
public enum AnnotationCropBox {
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The compression `AnnotationCrop` already passes to ImageIO.
    public static let jpegQuality = 0.85

    /// True when both stored sides are at least one pixel, using the absolute size.
    /// A negative stored size is the same mark flipped around its origin.
    public static func acceptsMark(width: Double, height: Double) -> Bool {
        let mark = CGRect(x: 0, y: 0, width: width, height: height)
        return mark.width >= 1 && mark.height >= 1
    }

    /// The pixel rectangle to crop, or nil when the mark is under one pixel or the overlap is.
    /// `width` and `height` are the stored size. Intersection standardizes a negative size,
    /// then keeps only an overlap of at least one pixel inside the image.
    public static func clip(
        x: Double, y: Double, width: Double, height: Double, imageWidth: Int, imageHeight: Int
    ) -> Rect? {
        let mark = CGRect(x: x, y: y, width: width, height: height)
        guard mark.width >= 1, mark.height >= 1 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let hit = mark.intersection(bounds)
        guard !hit.isNull, hit.width >= 1, hit.height >= 1 else { return nil }
        return Rect(x: Double(hit.origin.x), y: Double(hit.origin.y), width: Double(hit.width), height: Double(hit.height))
    }

    public static func markedLabel(_ label: String) -> String {
        label + " (marked crop)"
    }
}
