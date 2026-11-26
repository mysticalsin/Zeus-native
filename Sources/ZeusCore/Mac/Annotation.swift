import CoreGraphics
import Foundation

/// A stroke drawn on screen while holding left Control ("show me"). Points are global AppKit
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
        Self.cg(AnnotationBox.bounds(samples))
    }

    public var length: Double {
        AnnotationBox.length(samples)
    }

    public var shape: Shape {
        switch AnnotationBox.shape(samples) {
        case .circle: .circle
        case .line: .line
        case .spot: .spot
        case .scribble: .scribble
        }
    }

    /// The marked region, padded and clamped to `screen`. A line gets a band above and below
    /// (it marks text), a spot a small square.
    public func region(in screen: CGRect, padding: CGFloat = 12) -> CGRect {
        if screen.isNull { return .null }
        let frame = screen.isInfinite ? .zero : screen.standardized
        return Self.cg(AnnotationBox.region(
            samples, screenMinX: Double(frame.minX), screenMinY: Double(frame.minY),
            screenWidth: Double(frame.width), screenHeight: Double(frame.height),
            padding: Double(padding), clamp: !screen.isInfinite))
    }

    /// The region in screenshot pixels (top-left origin) for a shot of `displayFrame`.
    public static func pixelRect(_ region: CGRect, displayFrame: CGRect, pixelWidth: Int, pixelHeight: Int) -> CGRect {
        let rect = AnnotationBox.pixelRect(
            minX: Double(region.minX), maxY: Double(region.maxY),
            width: Double(region.width), height: Double(region.height),
            displayMinX: Double(displayFrame.minX), displayMaxY: Double(displayFrame.maxY),
            displayWidth: Double(displayFrame.width), displayHeight: Double(displayFrame.height),
            pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private var samples: [AnnotationBox.Point] {
        points.map { AnnotationBox.Point(x: Double($0.x), y: Double($0.y)) }
    }

    private static func cg(_ rect: AnnotationBox.Rect) -> CGRect {
        guard !rect.isNull else { return .null }
        return CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
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
