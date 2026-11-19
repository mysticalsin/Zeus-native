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
    public static let maxFlyOffDistance: CGFloat = 240

    /// The offset a flicked file flies to: along the flick, at most `maxFlyOffDistance` away. Reduce Motion only fades.
    public static func flyOff(translation: CGSize, reduceMotion: Bool) -> FlingFlyOff {
        if reduceMotion { return FlingFlyOff(offset: .zero, fadeOnly: true) }
        let distance = hypot(translation.width, translation.height)
        guard distance > maxFlyOffDistance else { return FlingFlyOff(offset: translation, fadeOnly: false) }
        let scale = maxFlyOffDistance / distance
        return FlingFlyOff(offset: CGSize(width: translation.width * scale, height: translation.height * scale), fadeOnly: false)
    }

    /// Where the `index`th floating paper goes: a cascade down and to the left from the top right corner of `area`
    /// (y grows upward), wrapping back to the corner before a paper would leave the area. A paper larger than the
    /// area is pinned to the area's lower left corner.
    public static func paperOrigin(index: Int, paper: CGSize, in area: CGRect) -> CGPoint {
        let step: CGFloat = 28, inset: CGFloat = 24
        let startX = area.maxX - paper.width - inset, startY = area.maxY - paper.height - inset
        let roomX = max(0, startX - area.minX - inset), roomY = max(0, startY - area.minY - inset)
        let steps = max(1, Int(min(roomX, roomY) / step) + 1)
        let k = CGFloat(index % steps)
        let x = min(max(startX - k * step, area.minX), max(area.minX, area.maxX - paper.width))
        let y = min(max(startY - k * step, area.minY), max(area.minY, area.maxY - paper.height))
        return CGPoint(x: x, y: y)
    }

    /// The offsets of a fanned stack of `count` papers, at most five. One paper is not a stack.
    public static func stackFan(count: Int) -> [CGPoint] {
        guard count > 1 else { return [] }
        return (0..<min(count, 5)).map { CGPoint(x: CGFloat($0) * 6, y: CGFloat(-$0) * 4) }
    }
}
