import Foundation

/// Which raster scale a mascot snapshot uses. Zero means the notch default.
public enum MascotRasterChoice {
    public static let notchDefault = 2.0

    /// A positive export scale is kept. Zero and anything below it use the notch default.
    public static func resolve(_ environment: Double) -> Double {
        environment > 0 ? environment : notchDefault
    }
}
