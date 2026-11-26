import Foundation

/// Peek hit testing as `Double` edges. The caller supplies the pointer and the screen.
/// This type does not read a pointer, a screen, or a clock.
public enum NotchPeekHitRulesBox {
    /// Room past the card so the edge is easy to hit.
    public static let slack = 6.0

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

    /// The card as drawn: centred on the screen, hanging from the top offset.
    /// A negative offset is treated as zero. The maximum edges are exclusive, matching `CGRect.contains`.
    public static func cardRect(width: Double, height: Double, screenMinX: Double, screenWidth: Double,
                                screenMaxY: Double, topOffset: Double) -> Rect {
        let midX = screenMinX + screenWidth / 2
        return Rect(x: midX - width / 2, y: screenMaxY - max(topOffset, 0) - height, width: width, height: height)
    }

    public static func takesMouse(x: Double, y: Double, width: Double, height: Double, screenMinX: Double,
                                  screenWidth: Double, screenMaxY: Double, topOffset: Double,
                                  slack: Double = NotchPeekHitRulesBox.slack) -> Bool {
        let card = cardRect(width: width, height: height, screenMinX: screenMinX, screenWidth: screenWidth,
                            screenMaxY: screenMaxY, topOffset: topOffset)
        let hit = Rect(x: card.x - slack, y: card.y - slack, width: card.width + slack * 2, height: card.height + slack * 2)
        return x >= hit.x && x < hit.x + hit.width && y >= hit.y && y < hit.y + hit.height
    }
}
