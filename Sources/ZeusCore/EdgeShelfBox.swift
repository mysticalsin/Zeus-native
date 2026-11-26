import Foundation

/// Where an edge-shelf sticky sits, as `Double` edges. A tucked card keeps its full size and slides
/// so only the tab stays on screen. The caller supplies the visible frame. This type does not read a
/// pointer, a screen, or a clock.
public enum EdgeShelfBox {
    public static let tabWidth: Double = 22
    public static let cardWidth: Double = 260
    public static let cardHeight: Double = 220
    /// A floating card within this many points of a side snaps to that side.
    public static let snapDistance: Double = 24

    public enum Edge: String, Equatable, Sendable {
        case left
        case right
    }

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

    /// `top` is the distance from the visible top down to the card's top. A negative top is zero.
    /// A top past the bottom of the visible frame stops at the bottom. The returned rect is always
    /// `width` by `height`; tucking changes only `x`.
    public static func frame(edge: Edge, top: Double, expanded: Bool,
                             visibleMinX: Double, visibleMaxX: Double,
                             visibleMaxY: Double, visibleHeight: Double,
                             width: Double = cardWidth, height: Double = cardHeight) -> Rect {
        let clampedTop = min(max(top, 0), max(visibleHeight - height, 0))
        let y = visibleMaxY - clampedTop - height
        let shown = expanded ? width : tabWidth
        let x = edge == .left ? visibleMinX - width + shown : visibleMaxX - shown
        return Rect(x: x, y: y, width: width, height: height)
    }

    /// The nearer side when the card is within `snap` points of it. The left side wins when both are.
    public static func snapEdge(frameMinX: Double, frameMaxX: Double,
                                visibleMinX: Double, visibleMaxX: Double,
                                snap: Double = snapDistance) -> Edge? {
        if frameMinX - visibleMinX <= snap { return .left }
        if visibleMaxX - frameMaxX <= snap { return .right }
        return nil
    }

    /// The `top` value that keeps a card where it was dropped. A card above the visible top is zero.
    public static func top(frameMaxY: Double, visibleMaxY: Double) -> Double {
        max(0, visibleMaxY - frameMaxY)
    }
}
