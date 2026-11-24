import Foundation

/// How close a ring or trail must land, in physical pixels.
/// 24 px at 1080p (scale 1). 48 px at 4K: scale 2, or a panel at least 3840 px wide.
public enum PresentTolerance {
    public static let ringPixels1080p: Double = 24
    public static let ringPixels4K: Double = 48

    public enum Band: Equatable, Sendable {
        case standard
        case fine
    }

    public struct Decision: Equatable, Sendable {
        public var band: Band
        public var pixels: Double
        public var points: Double

        public init(band: Band, pixels: Double, points: Double) {
            self.band = band
            self.pixels = pixels
            self.points = points
        }
    }

    /// The band, the pixel budget and the point budget for one display.
    public static func decide(scale: Double, pixelWidth: Int) -> Decision {
        let pixels = ringPixels(scale: scale, pixelWidth: pixelWidth)
        let points = ringPoints(scale: scale, pixelWidth: pixelWidth)
        return Decision(band: pixels == ringPixels4K ? .fine : .standard, pixels: pixels, points: points)
    }

    public static func ringPixels(scale: Double, pixelWidth: Int) -> Double {
        if scale >= 2 || pixelWidth >= 3840 { return ringPixels4K }
        return ringPixels1080p
    }

    /// The same budget in points. 24 pt on 1080p and on 2x Retina. 48 pt on a 4K panel at scale 1.
    public static func ringPoints(scale: Double, pixelWidth: Int) -> Double {
        let safe = scale > 0 ? scale : 1
        return ringPixels(scale: safe, pixelWidth: pixelWidth) / safe
    }
}
