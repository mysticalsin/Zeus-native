import CoreGraphics
import SwiftUI

/// Matches `ImageRenderer.scale` when drawing mascots so 1x snapshots pick crisp pixels.
public struct MascotRasterScaleKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
    /// When zero, views use 2x rasterisation (notch default). Snapshots set this to the export scale.
    var mascotRasterScale: CGFloat {
        get { self[MascotRasterScaleKey.self] }
        set { self[MascotRasterScaleKey.self] = newValue }
    }
}

public enum MascotRasterScale {
    public static func resolve(_ environment: CGFloat) -> CGFloat {
        environment > 0 ? environment : 2
    }
}
