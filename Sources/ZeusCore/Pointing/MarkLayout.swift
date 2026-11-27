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
public struct PlacedScreenMark: Equatable, Sendable {
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

    public func place(_ marks: [MarkPin]) -> [PlacedScreenMark] {
        let current = screens()
        return marks.compactMap { mark in
            guard let screen = current.first(where: { Self.owns(mark.point, on: $0, among: current) }) else { return nil }
            return PlacedScreenMark(number: mark.number, title: mark.title, screenID: screen.id,
                              local: Self.local(mark.point, on: screen),
                              accessibilityLabel: "Mark \(mark.number), \(mark.title)")
        }
    }

    /// Includes the far edges `CGRect.contains` leaves out. A shared edge stays with the screen
    /// whose minimum edge it is, so it is not drawn twice.
    static func owns(_ point: CGPoint, on screen: MarkScreen, among screens: [MarkScreen]) -> Bool {
        let frame = screen.frame
        guard point.x >= frame.minX, point.x <= frame.maxX, point.y >= frame.minY, point.y <= frame.maxY else { return false }
        let onFarEdge = point.x == frame.maxX || point.y == frame.maxY
        guard onFarEdge else { return true }
        return !screens.contains { other in other.id != screen.id && other.frame.contains(point) }
    }

    /// Flip into one screen. The screen's own height is the top, not a shared window.
    public static func local(_ point: CGPoint, on screen: MarkScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX,
                y: screen.frame.height - (point.y - screen.frame.minY))
    }
}
