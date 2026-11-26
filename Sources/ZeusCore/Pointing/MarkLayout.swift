import Foundation

/// One attached display, in global points. The origin is the bottom-left corner.
public struct MarkScreen: Equatable, Sendable, Identifiable {
    public var id: String
    public var frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// A numbered mark in global points.
public struct MarkPin: Equatable, Sendable {
    public var number: Int
    public var title: String
    public var point: CGPoint

    public init(number: Int, title: String, point: CGPoint) {
        self.number = number
        self.title = title
        self.point = point
    }
}

/// Where one mark sits after the screens are read, in that screen's own view coordinates.
public struct PlacedMark: Equatable, Sendable {
    public var number: Int
    public var title: String
    public var screenID: String
    public var local: CGPoint
    public var accessibilityLabel: String
}

/// Places marks on the screens a provider returns. A mark whose screen is gone is not placed.
public struct MarkLayout {
    public var screens: () -> [MarkScreen]

    public init(screens: @escaping () -> [MarkScreen]) {
        self.screens = screens
    }

    public func place(_ marks: [MarkPin]) -> [PlacedMark] {
        let current = screens()
        return marks.compactMap { mark in
            guard let screen = current.first(where: { Self.owns(mark.point, on: $0) }) else { return nil }
            return PlacedMark(number: mark.number, title: mark.title, screenID: screen.id,
                              local: Self.local(mark.point, on: screen),
                              accessibilityLabel: "Mark \(mark.number), \(mark.title)")
        }
    }

    /// The minimum corner is inside the frame. The maximum corner is too: it is the one point
    /// `CGRect.contains` leaves outside.
    static func owns(_ point: CGPoint, on screen: MarkScreen) -> Bool {
        if screen.frame.contains(point) { return true }
        return point.x == screen.frame.maxX && point.y == screen.frame.maxY
    }

    /// Flip into one screen. The screen's own height is the top, not a shared window.
    public static func local(_ point: CGPoint, on screen: MarkScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX,
                y: screen.frame.height - (point.y - screen.frame.minY))
    }
}
