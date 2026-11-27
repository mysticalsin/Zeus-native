import CoreGraphics
import CZeusVisual
import ZeusCore

/// Flight and frame size from `crates/zeus-visual`. The ring and the overlay stay in Swift.
enum VisualFlight {
    static func plan(from: CGPoint, to: CGPoint, reducedMotion: Bool) -> CompanionFlight {
        let raw = zeus_visual_flight(Double(from.x), Double(from.y), Double(to.x), Double(to.y), reducedMotion ? 1 : 0)
        return CompanionFlight(
            from: CGPoint(x: raw.from_x, y: raw.from_y),
            control: CGPoint(x: raw.control_x, y: raw.control_y),
            to: CGPoint(x: raw.to_x, y: raw.to_y),
            duration: raw.duration,
            reducedMotion: raw.reduced_motion != 0)
    }

    static func pixelSize(width: Double, height: Double, scale: Double) -> (width: Int, height: Int) {
        let raw = zeus_visual_pixel_size(width, height, scale)
        return (Int(raw.width), Int(raw.height))
    }
}
