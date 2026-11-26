import CoreGraphics
import Foundation

/// Where a flicked file goes, and how it gets there.
public struct FlingFlyOff: Equatable, Sendable {
    public var offset: CGSize
    /// True under Reduce Motion: the file fades where it is instead of travelling.
    public var fadeOnly: Bool
}

public enum FlingGeometry {
    /// A flicked file never travels further than this on screen.
    public static let maxFlyOffDistance: CGFloat = CGFloat(FlingLayoutBox.maxFlyOffDistance)

    /// The offset a flicked file flies to: along the flick, at most `maxFlyOffDistance` away. Reduce Motion only fades.
    public static func flyOff(translation: CGSize, reduceMotion: Bool) -> FlingFlyOff {
        let box = FlingLayoutBox.flyOff(width: Double(translation.width), height: Double(translation.height), reduceMotion: reduceMotion)
        return FlingFlyOff(offset: CGSize(width: box.width, height: box.height), fadeOnly: box.fadeOnly)
    }

    /// Where the `index`th floating paper goes: a cascade down and to the left from the top right corner of `area`
    /// (y grows upward), wrapping back to the corner before a paper would leave the area. A paper larger than the
    /// area is pinned to the area's lower left corner.
    public static func paperOrigin(index: Int, paper: CGSize, in area: CGRect) -> CGPoint {
        let origin = FlingLayoutBox.paperOrigin(
            index: index,
            paperWidth: Double(paper.width),
            paperHeight: Double(paper.height),
            minX: Double(area.minX),
            minY: Double(area.minY),
            maxX: Double(area.maxX),
            maxY: Double(area.maxY))
        return CGPoint(x: origin.x, y: origin.y)
    }

    /// The offsets of a fanned stack of `count` papers, at most five. One paper is not a stack.
    public static func stackFan(count: Int) -> [CGPoint] {
        FlingLayoutBox.stackFan(count: count).map { CGPoint(x: $0.x, y: $0.y) }
    }
}
