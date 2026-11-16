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
}
