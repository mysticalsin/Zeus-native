import CoreGraphics
import Foundation

/// A stroke drawn on screen while holding Command ("show me"). Points are global AppKit
/// coordinates (bottom-left origin), in the order they were drawn.
public struct AnnotationStroke: Equatable, Sendable {
    public enum Shape: String, Equatable, Sendable {
        /// A loop around something: the region is what is inside it.
        case circle
        /// A mostly straight line: under or through a word or row.
        case line
        /// A tap or tiny scribble: one spot.
        case spot
        /// Anything else: its bounding box.
        case scribble
    }

    public var points: [CGPoint]

    public init(points: [CGPoint]) { self.points = points }

    public var bounds: CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }

    public var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    public var shape: Shape {
        let box = bounds
        let diagonal = hypot(box.width, box.height)
        guard points.count > 2, diagonal >= 12 else { return .spot }
        let gap = hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y)
        // Closed: the ends meet (within a third of the size) after going around at least once.
        if gap <= diagonal / 3, length >= diagonal * 2 { return .circle }
        if length <= diagonal * 1.25 { return .line }
        return .scribble
    }

    /// The marked region, padded and clamped to `screen`. A line gets a band above and below
    /// (it marks text), a spot a small square.
    public func region(in screen: CGRect, padding: CGFloat = 12) -> CGRect {
        var box = bounds
        guard !box.isNull else { return .null }
        switch shape {
        case .spot: box = box.insetBy(dx: -40, dy: -40)
        case .line: box = box.insetBy(dx: -padding, dy: -max(padding, 24))
        case .circle, .scribble: box = box.insetBy(dx: -padding, dy: -padding)
        }
        return box.intersection(screen)
    }

    /// The region in screenshot pixels (top-left origin) for a shot of `displayFrame`.
    public static func pixelRect(_ region: CGRect, displayFrame: CGRect, pixelWidth: Int, pixelHeight: Int) -> CGRect {
        let sx = Double(pixelWidth) / displayFrame.width
        let sy = Double(pixelHeight) / displayFrame.height
        let x = (region.minX - displayFrame.minX) * sx
        let y = (displayFrame.maxY - region.maxY) * sy
        return CGRect(x: x.rounded(), y: y.rounded(), width: (region.width * sx).rounded(), height: (region.height * sy).rounded())
    }

    /// What the brain is told about the mark, next to the screenshot it was drawn on.
    public func prompt(question: String?, pixels: CGRect, screen: Int, shape drawn: Shape? = nil) -> String {
        let r = "x=\(Int(pixels.minX)) y=\(Int(pixels.minY)) w=\(Int(pixels.width)) h=\(Int(pixels.height))"
        let how: String
        switch drawn ?? shape {
        case .circle: how = "circled"
        case .line: how = "underlined"
        case .spot: how = "tapped"
        case .scribble: how = "marked"
        }
        let ask = question?.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = (ask?.isEmpty == false) ? ask! : "What is this, and what should I do with it?"
        return "I \(how) a spot on screen \(screen) at \(r) (screenshot pixels, top-left origin). "
            + "Answer about that spot only. \(q)"
    }
}
