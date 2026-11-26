import Foundation

/// Flick travel, paper placement, and the stack fan as Doubles. `FlingGeometry` keeps the CoreGraphics types.
public struct FlingFlyOffBox: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var fadeOnly: Bool

    public init(width: Double, height: Double, fadeOnly: Bool) {
        self.width = width
        self.height = height
        self.fadeOnly = fadeOnly
    }
}

public enum FlingLayoutBox {
    /// A flicked file never travels further than this on screen.
    public static let maxFlyOffDistance = 240.0
    /// Cascade step and the inset from the area edge, in points.
    public static let paperStep = 28.0
    public static let paperInset = 24.0

    /// The offset a flicked file flies to, along the flick, at most `maxFlyOffDistance` away.
    /// Reduce Motion only fades.
    public static func flyOff(width: Double, height: Double, reduceMotion: Bool) -> FlingFlyOffBox {
        if reduceMotion { return FlingFlyOffBox(width: 0, height: 0, fadeOnly: true) }
        let distance = (width * width + height * height).squareRoot()
        guard distance > maxFlyOffDistance else {
            return FlingFlyOffBox(width: width, height: height, fadeOnly: false)
        }
        let scale = maxFlyOffDistance / distance
        return FlingFlyOffBox(width: width * scale, height: height * scale, fadeOnly: false)
    }

    /// Where the `index`th floating paper goes. Y grows upward. A paper larger than the area
    /// is pinned to the area's lower left corner.
    public static func paperOrigin(
        index: Int,
        paperWidth: Double,
        paperHeight: Double,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) -> (x: Double, y: Double) {
        let startX = maxX - paperWidth - paperInset
        let startY = maxY - paperHeight - paperInset
        let roomX = max(0, startX - minX - paperInset)
        let roomY = max(0, startY - minY - paperInset)
        let steps = max(1, Int(min(roomX, roomY) / paperStep) + 1)
        let k = Double(index % steps)
        let x = min(max(startX - k * paperStep, minX), max(minX, maxX - paperWidth))
        let y = min(max(startY - k * paperStep, minY), max(minY, maxY - paperHeight))
        return (x, y)
    }

    /// Offsets of a fanned stack, at most five. One paper is not a stack.
    public static func stackFan(count: Int) -> [(x: Double, y: Double)] {
        guard count > 1 else { return [] }
        return (0..<min(count, 5)).map { (x: Double($0) * 6, y: Double(-$0) * 4) }
    }
}
