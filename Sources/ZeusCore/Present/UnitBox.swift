import Foundation

/// A point used while measuring a mark. The overlay's CoreGraphics point is built from this later.
public struct UnitSample: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One straight stroke, sampled the same way a label checks whether it sits on the line.
public struct UnitSegment: Equatable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }
}

public enum UnitStroke: Equatable, Sendable {
    case segment(UnitSegment)
    case path([UnitSegment])
}

/// An axis-aligned box in unit space. Null, union, inset and contains follow the rectangle the
/// overlay used before this type existed.
public struct UnitBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var isNull: Bool

    public init(x: Double, y: Double, width: Double, height: Double, isNull: Bool = false) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isNull = isNull
    }

    public static let null = UnitBox(x: .infinity, y: .infinity, width: 0, height: 0, isNull: true)

    public var minX: Double { width < 0 ? x + width : x }
    public var maxX: Double { width < 0 ? x : x + width }
    public var minY: Double { height < 0 ? y + height : y }
    public var maxY: Double { height < 0 ? y : y + height }

    public func insetBy(dx: Double, dy: Double) -> UnitBox {
        if isNull { return .null }
        let nextWidth = width - dx * 2
        let nextHeight = height - dy * 2
        if nextWidth < 0 || nextHeight < 0 { return .null }
        return UnitBox(x: x + dx, y: y + dy, width: nextWidth, height: nextHeight)
    }

    public func union(_ other: UnitBox) -> UnitBox {
        if isNull { return other }
        if other.isNull { return self }
        let left = min(minX, other.minX)
        let top = min(minY, other.minY)
        let right = max(maxX, other.maxX)
        let bottom = max(maxY, other.maxY)
        return UnitBox(x: left, y: top, width: right - left, height: bottom - top)
    }

    public func offsetBy(dx: Double, dy: Double) -> UnitBox {
        if isNull { return .null }
        return UnitBox(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        if isNull { return false }
        return px >= minX && px < maxX && py >= minY && py < maxY
    }

    /// Seventeen samples, the endpoints included. A crossing that falls between samples does not hit.
    public func hitsSegment(_ segment: UnitSegment, samples: Int = 16) -> Bool {
        if isNull || samples <= 0 { return false }
        for step in 0...samples {
            let t = Double(step) / Double(samples)
            let px = segment.x0 + (segment.x1 - segment.x0) * t
            let py = segment.y0 + (segment.y1 - segment.y0) * t
            if contains(x: px, y: py) { return true }
        }
        return false
    }

    /// A label overlaps a stroke when the box, grown by 0.02, contains a sample of the stroke.
    public func overlaps(_ stroke: UnitStroke) -> Bool {
        if isNull { return false }
        let grown = insetBy(dx: -0.02, dy: -0.02)
        if grown.isNull { return false }
        switch stroke {
        case .segment(let segment):
            return grown.hitsSegment(segment)
        case .path(let segments):
            return segments.contains { grown.hitsSegment($0) }
        }
    }

    public static func rect(x: Double, y: Double, width: Double, height: Double) -> UnitBox {
        UnitBox(x: x, y: y, width: width, height: height)
    }

    public static func circle(centerX: Double, centerY: Double, radius: Double) -> UnitBox {
        UnitBox(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
    }

    public static func segment(x0: Double, y0: Double, x1: Double, y1: Double) -> UnitBox {
        UnitBox(x: min(x0, x1), y: min(y0, y1), width: abs(x1 - x0), height: abs(y1 - y0))
            .insetBy(dx: -0.01, dy: -0.01)
    }

    public static func path(_ points: [UnitSample]) -> UnitBox? {
        guard let first = points.first else { return nil }
        var rect = UnitBox(x: first.x, y: first.y, width: 0, height: 0)
        for point in points.dropFirst() {
            rect = rect.union(UnitBox(x: point.x, y: point.y, width: 0, height: 0))
        }
        return rect.insetBy(dx: -0.01, dy: -0.01)
    }

    public static func label(characterCount: Int, x: Double, y: Double) -> UnitBox {
        let width = max(0.03, Double(characterCount) * 0.018)
        return UnitBox(x: x - width / 2, y: y - 0.02, width: width, height: 0.04)
    }

    public static func math(spokenCount: Int, hasNumerator: Bool, x: Double, y: Double) -> UnitBox {
        let width = max(0.08, Double(spokenCount) * 0.016)
        let height = hasNumerator ? 0.09 : 0.05
        return UnitBox(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
}

/// Moves a label off strokes, at most eight times, by 0.03 each time.
public enum LabelNudge {
    public static let maxSteps = 8
    public static let dy = 0.03

    public enum State: Equatable, Sendable {
        case checking(step: Int, box: UnitBox)
        case settled(UnitBox)
        case capped(UnitBox)

        public var box: UnitBox {
            switch self {
            case .checking(_, let box), .settled(let box), .capped(let box): box
            }
        }
    }

    public enum Event: Equatable, Sendable {
        case overlapped
        case clear
    }

    /// A settled or capped nudge ignores further events. An overlapped check at the step limit caps in place.
    public static func reduce(_ state: State, _ event: Event) -> State {
        guard case .checking(let step, let box) = state else { return state }
        switch event {
        case .clear:
            return .settled(box)
        case .overlapped:
            guard step < maxSteps else { return .capped(box) }
            return .checking(step: step + 1, box: box.offsetBy(dx: 0, dy: dy))
        }
    }

    public static func place(_ box: UnitBox, overlapping: (UnitBox) -> Bool) -> State {
        var state = State.checking(step: 0, box: box)
        while case .checking(let step, let current) = state, step < maxSteps {
            state = reduce(state, overlapping(current) ? .overlapped : .clear)
        }
        if case .checking(_, let current) = state {
            return .capped(current)
        }
        return state
    }
}
