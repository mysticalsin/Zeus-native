import Foundation

/// One drag sample as Doubles. `FlingFlick` keeps the CoreGraphics point.
public struct FlickPointBox: Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double

    public init(time: Double, x: Double, y: Double) {
        self.time = time
        self.x = x
        self.y = y
    }
}

public enum FlickOutcomeBox: Equatable, Sendable {
    case drop
    case send(peerIndex: Int)
    case picker
}

/// Flick speed and direction as Doubles. `FlingFlick` keeps the CoreGraphics types.
public enum FlingFlickBox {
    /// Seconds at the end of the drag that count toward the speed.
    public static let window = 0.08
    /// Points per second. Low, normal, and high match the shelf sensitivity.
    public static let lowThreshold = 1800.0
    public static let normalThreshold = 1200.0
    public static let highThreshold = 800.0

    /// Points are in screen space with y growing downward, so up is negative y.
    /// `peers` counts the Macs a flick may reach. With none, a fast flick opens the picker.
    public static func classify(samples: [FlickPointBox], threshold: Double, peers: Int) -> FlickOutcomeBox {
        guard let last = samples.last else { return .drop }
        let recent = samples.filter { $0.time >= last.time - window - 1e-9 }
        guard let first = recent.first, last.time > first.time else { return .drop }
        let dt = last.time - first.time
        let dx = last.x - first.x
        let dy = last.y - first.y
        let speed = (dx * dx + dy * dy).squareRoot() / dt
        guard speed >= threshold else { return .drop }
        if peers <= 0 { return .picker }
        if peers == 1 { return .send(peerIndex: 0) }
        if abs(dy) > abs(dx) { return dy < 0 ? .picker : .drop }
        return .send(peerIndex: dx < 0 ? 0 : peers - 1)
    }
}
