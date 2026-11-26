import Foundation

/// Show-me stroke geometry as `Double` samples. The caller supplies the points and the screen.
/// This type does not read a pointer, a screen, or a clock.
public enum AnnotationBox {
    public enum Shape: String, Equatable, Sendable {
        case circle
        case line
        case spot
        case scribble
    }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var isNull: Bool

        public init(x: Double, y: Double, width: Double, height: Double, isNull: Bool) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.isNull = isNull
        }

        public static let null = Rect(x: .infinity, y: .infinity, width: 0, height: 0, isNull: true)
    }

    /// The bounding box of the samples. No samples is null. One sample is a zero-size rect at that point.
    public static func bounds(_ points: [Point]) -> Rect {
        guard let first = points.first else { return .null }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY, isNull: false)
    }

    /// The length of the polyline, in the order the samples were drawn.
    public static func length(_ points: [Point]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        var previous = points[0]
        for point in points.dropFirst() {
            total += distance(previous, point)
            previous = point
        }
        return total
    }

    /// A loop around something, a mostly straight line, a tap, or anything else.
    /// Fewer than three samples, or a diagonal under 12, is a spot.
    public static func shape(_ points: [Point]) -> Shape {
        let box = bounds(points)
        let diagonal = box.isNull ? 0 : distance(box.width, box.height)
        guard points.count > 2, diagonal >= 12 else { return .spot }
        let gap = distance(points[0], points[points.count - 1])
        let drawn = length(points)
        if gap <= diagonal / 3, drawn >= diagonal * 2 { return .circle }
        if drawn <= diagonal * 1.25 { return .line }
        return .scribble
    }

    /// The marked region, padded and clamped to the screen. A line gets a band above and below.
    /// A spot gets a small square. A miss, or no samples, is null.
    public static func region(_ points: [Point], screenMinX: Double, screenMinY: Double,
                              screenWidth: Double, screenHeight: Double, padding: Double = 12,
                              clamp: Bool = true) -> Rect {
        let box = bounds(points)
        guard !box.isNull else { return .null }
        let padX: Double
        let padY: Double
        switch shape(points) {
        case .spot:
            padX = 40
            padY = 40
        case .line:
            padX = padding
            padY = max(padding, 24)
        case .circle, .scribble:
            padX = padding
            padY = padding
        }
        let expanded = inset(box, dx: -padX, dy: -padY)
        guard clamp else { return expanded }
        let screen = Rect(x: screenMinX, y: screenMinY, width: screenWidth, height: screenHeight, isNull: false)
        return intersection(expanded, screen)
    }

    /// Screenshot pixels for a region on a display. Origin is the top left. Edges round to the nearest pixel.
    public static func pixelRect(minX: Double, maxY: Double, width: Double, height: Double,
                                 displayMinX: Double, displayMaxY: Double,
                                 displayWidth: Double, displayHeight: Double,
                                 pixelWidth: Int, pixelHeight: Int) -> Rect {
        let scaleX = Double(pixelWidth) / displayWidth
        let scaleY = Double(pixelHeight) / displayHeight
        return Rect(
            x: ((minX - displayMinX) * scaleX).rounded(),
            y: ((displayMaxY - maxY) * scaleY).rounded(),
            width: (width * scaleX).rounded(),
            height: (height * scaleY).rounded(),
            isNull: false)
    }

    private static func distance(_ width: Double, _ height: Double) -> Double {
        (width * width + height * height).squareRoot()
    }

    private static func distance(_ start: Point, _ end: Point) -> Double {
        distance(end.x - start.x, end.y - start.y)
    }

    /// Same contract as `CGRect.insetBy`: a negative inset grows the rect, and a negative result is null.
    private static func inset(_ rect: Rect, dx: Double, dy: Double) -> Rect {
        if rect.isNull { return .null }
        let width = rect.width - dx * 2
        let height = rect.height - dy * 2
        if width < 0 || height < 0 { return .null }
        return Rect(x: rect.x + dx, y: rect.y + dy, width: width, height: height, isNull: false)
    }

    /// Same contract as `CGRect.intersection`: no overlap, or a zero-area overlap, is null.
    private static func intersection(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let a = standardized(lhs)
        let b = standardized(rhs)
        if a.isNull || b.isNull { return .null }
        let x1 = max(a.x, b.x)
        let y1 = max(a.y, b.y)
        let x2 = min(a.x + a.width, b.x + b.width)
        let y2 = min(a.y + a.height, b.y + b.height)
        if x2 <= x1 || y2 <= y1 { return .null }
        return Rect(x: x1, y: y1, width: x2 - x1, height: y2 - y1, isNull: false)
    }

    private static func standardized(_ rect: Rect) -> Rect {
        if rect.isNull { return .null }
        var x = rect.x
        var y = rect.y
        var width = rect.width
        var height = rect.height
        if width < 0 {
            x += width
            width = -width
        }
        if height < 0 {
            y += height
            height = -height
        }
        return Rect(x: x, y: y, width: width, height: height, isNull: false)
    }
}
