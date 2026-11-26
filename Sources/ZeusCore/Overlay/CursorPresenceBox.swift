import Foundation

/// Where the cursor pill sits, as `Double` points. A window that would leave the screen flips
/// to the other side of the pointer, then moves clear of a nearby caret. This type does not
/// read a pointer, a screen, or a clock.
public enum CursorAnchorBox {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
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

    /// AppKit-style rectangle. The minimum edges are inside. The maximum edges are outside.
    /// Touching edges do not intersect.
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

        public var minX: Double { x }
        public var minY: Double { y }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }

        public func contains(_ point: Point) -> Bool {
            point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
        }

        public func insetBy(dx: Double, dy: Double) -> Rect {
            Rect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
        }

        public func intersects(_ other: Rect) -> Bool {
            !(maxX <= other.minX || other.maxX <= minX || maxY <= other.minY || other.maxY <= minY)
        }
    }

    public static let defaultOffset = Point(x: 18, y: -18)
    /// Never closer than this to a caret rect, so the window never covers text being typed.
    public static let defaultCaretMargin = 24.0

    /// The frame a `size`-sized window should take, anchored near `cursor`, kept fully inside
    /// `screenFrame`, flipped to the opposite side of the pointer when the plain offset would
    /// run off an edge, and pushed clear of `caretRect` (if given) by at least `caretMargin`.
    public static func frame(cursor: Point, size: Size, screenFrame: Rect,
                              offset: Point = defaultOffset, caretRect: Rect? = nil,
                              caretMargin: Double = defaultCaretMargin) -> Rect {
        guard size.width > 0, size.height > 0 else {
            return Rect(x: cursor.x, y: cursor.y, width: size.width, height: size.height)
        }
        guard screenFrame.width >= size.width, screenFrame.height >= size.height else {
            return Rect(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2,
                        width: size.width, height: size.height)
        }
        // Down from the pointer means the box's top sits `offset.y` below the pointer, so the
        // bottom-left origin is a further `size.height` down.
        var originX = cursor.x + offset.x
        var originY = cursor.y + offset.y - size.height
        if originX + size.width > screenFrame.maxX {
            originX = cursor.x - offset.x - size.width
        }
        if originY < screenFrame.minY {
            originY = cursor.y - offset.y
        }
        originX = min(max(originX, screenFrame.minX), screenFrame.maxX - size.width)
        originY = min(max(originY, screenFrame.minY), screenFrame.maxY - size.height)
        var rect = Rect(x: originX, y: originY, width: size.width, height: size.height)
        // Only dodge a caret that is actually near the pointer. A stale caret far from the
        // pointer must not shove the pill away.
        let caretNear = caretRect.map { distance(Point(x: $0.midX, y: $0.midY), cursor) <= 160 } ?? false
        if caretNear, let caretRect, rect.insetBy(dx: -caretMargin, dy: -caretMargin).intersects(caretRect) {
            let below = caretRect.minY - caretMargin - size.height
            if below >= screenFrame.minY {
                rect.y = below
            } else {
                rect.y = min(caretRect.maxY + caretMargin, screenFrame.maxY - size.height)
            }
        }
        return rect
    }

    /// Which display's frame the cursor is over. Falls back to `main`, then the first screen.
    public static func screenFrame(containing cursor: Point, screens: [Rect], main: Rect?) -> Rect {
        if let match = screens.first(where: { $0.contains(cursor) }) { return match }
        if let main { return main }
        return screens.first ?? Rect(x: 0, y: 0, width: 0, height: 0)
    }

    /// Converts one rectangle between AppKit (y up) and Quartz (y down). The same formula
    /// runs in either direction.
    public static func flipToQuartz(_ rect: Rect, mainScreenHeight: Double) -> Rect {
        Rect(x: rect.x, y: mainScreenHeight - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A delayed pill hide must not tear down cursor presence while a new hold-to-speak turn is active.
public enum CursorPresenceGuardBox {
    public static func delayedPillHideShouldStopPresence(isActiveDictation: Bool) -> Bool {
        !isActiveDictation
    }
}

/// Exponential ease toward a target: `1 - exp(-dt * rate)`.
public enum SpringFollowBox {
    public static let defaultRate = 28.0

    public static func step(current: CursorAnchorBox.Point, target: CursorAnchorBox.Point, dt: Double,
                             rate: Double = defaultRate) -> CursorAnchorBox.Point {
        guard dt.isFinite, dt > 0 else { return current }
        let k = 1 - exp(-dt * rate)
        return CursorAnchorBox.Point(x: current.x + (target.x - current.x) * k,
                                      y: current.y + (target.y - current.y) * k)
    }

    public static func isSettled(current: CursorAnchorBox.Point, target: CursorAnchorBox.Point,
                                  epsilon: Double = 0.25) -> Bool {
        CursorAnchorBox.distance(current, target) <= epsilon
    }
}
