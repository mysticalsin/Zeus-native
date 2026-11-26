// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceDetector.swift, FaceRecognitionPipeline.swift.
import Foundation

/// Face picking and crop rectangles as `Double`s. Normalized boxes keep Vision's origin at the bottom
/// left. This type does not read a camera, an image, or a clock.
public enum FaceSelectionBox {
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

    public struct Size: Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// A face narrower than this fraction of the frame is a bystander, not a candidate.
    public static let minimumWidth = 0.18
    /// The most a face centre may drift between frames and still count as the same person.
    public static let continuityTolerance = 0.3
    /// Fraction of the face box added on each side before cropping.
    public static let cropPadding = 0.2

    /// The face to analyse: wide enough to be a candidate, then the one closest to the previous frame's face
    /// when that is near enough, else the largest. Continuity stops two similar faces from swapping every frame.
    public static func select(in boxes: [Rect], preferNear previous: Rect?) -> Int? {
        let candidates = boxes.indices.filter { isUsable(boxes[$0]) && boxes[$0].width >= minimumWidth }
        guard !candidates.isEmpty else { return nil }

        if let previous, isUsable(previous) {
            var nearest = candidates[0]
            for index in candidates.dropFirst()
                where distance(boxes[index], previous) < distance(boxes[nearest], previous) {
                nearest = index
            }
            if distance(boxes[nearest], previous) < continuityTolerance { return nearest }
        }
        return largest(among: candidates, in: boxes)
    }

    /// The largest face by area with no width floor, so enrollment can tell "too far away" from "nobody there".
    public static func largest(in boxes: [Rect]) -> Int? {
        largest(among: boxes.indices.filter { isUsable(boxes[$0]) }, in: boxes)
    }

    /// A normalized rectangle (origin bottom left) as a pixel rectangle with the origin at the top left.
    public static func imageRect(fromNormalized rect: Rect, imageSize: Size) -> Rect {
        let width = rect.width * imageSize.width
        let height = rect.height * imageSize.height
        return Rect(x: rect.x * imageSize.width,
                    y: (1 - rect.y) * imageSize.height - height,
                    width: width,
                    height: height)
    }

    /// The face box grown by `padding` on each side, snapped out to whole pixels, and clipped to the image.
    /// Nil when nothing is left.
    public static func paddedCrop(_ box: Rect, imageSize: Size, padding: Double = cropPadding) -> Rect? {
        guard isUsable(box), imageSize.width.isFinite, imageSize.height.isFinite else { return nil }
        let grown = inset(box, dx: -box.width * padding, dy: -box.height * padding)
        guard let whole = integral(grown) else { return nil }
        let bounds = Rect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        guard let clipped = intersection(whole, bounds), clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    private static func largest(among indices: [Int], in boxes: [Rect]) -> Int? {
        guard var best = indices.first else { return nil }
        for index in indices.dropFirst() where area(boxes[index]) > area(boxes[best]) { best = index }
        return best
    }

    private static func isUsable(_ rect: Rect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func area(_ rect: Rect) -> Double { rect.width * rect.height }

    private static func distance(_ box: Rect, _ anchor: Rect) -> Double {
        let dx = (box.x + box.width / 2) - (anchor.x + anchor.width / 2)
        let dy = (box.y + box.height / 2) - (anchor.y + anchor.height / 2)
        return hypot(dx, dy)
    }

    /// Same growth rule as `CGRect.insetBy`: a negative delta expands the box.
    private static func inset(_ rect: Rect, dx: Double, dy: Double) -> Rect {
        Rect(x: rect.x + dx, y: rect.y + dy, width: rect.width - 2 * dx, height: rect.height - 2 * dy)
    }

    /// Smallest whole-pixel rectangle that contains `rect`. Nil when a coordinate is not finite.
    private static func integral(_ rect: Rect) -> Rect? {
        guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        let minX = min(rect.x, rect.x + rect.width)
        let minY = min(rect.y, rect.y + rect.height)
        let maxX = max(rect.x, rect.x + rect.width)
        let maxY = max(rect.y, rect.y + rect.height)
        let left = floor(minX)
        let top = floor(minY)
        let right = ceil(maxX)
        let bottom = ceil(maxY)
        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Overlap of the two rectangles, or nil when they only touch or one is not finite.
    private static func intersection(_ a: Rect, _ b: Rect) -> Rect? {
        guard a.x.isFinite, a.y.isFinite, a.width.isFinite, a.height.isFinite,
              b.x.isFinite, b.y.isFinite, b.width.isFinite, b.height.isFinite else { return nil }
        let minX = max(min(a.x, a.x + a.width), min(b.x, b.x + b.width))
        let minY = max(min(a.y, a.y + a.height), min(b.y, b.y + b.height))
        let maxX = min(max(a.x, a.x + a.width), max(b.x, b.x + b.width))
        let maxY = min(max(a.y, a.y + a.height), max(b.y, b.y + b.height))
        guard minX < maxX, minY < maxY else { return nil }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
