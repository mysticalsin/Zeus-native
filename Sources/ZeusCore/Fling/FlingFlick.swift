import CoreGraphics
import Foundation

public struct FlickSample: Equatable, Sendable {
    public var time: TimeInterval
    public var point: CGPoint
    public init(time: TimeInterval, point: CGPoint) { self.time = time; self.point = point }
}

public enum FlickSensitivity: String, CaseIterable, Sendable {
    case low, normal, high
    /// Points per second, measured over the last 80 ms of the drag.
    public var threshold: CGFloat {
        switch self {
        case .low: return CGFloat(FlingFlickBox.lowThreshold)
        case .normal: return CGFloat(FlingFlickBox.normalThreshold)
        case .high: return CGFloat(FlingFlickBox.highThreshold)
        }
    }
}

public enum FlickOutcome: Equatable, Sendable {
    case drop
    case send(peerIndex: Int)
    case picker
}

public enum FlingFlick {
    public static let window: TimeInterval = FlingFlickBox.window

    /// Points are in screen space with y growing downward, so up is negative y. `peers` counts the Macs a flick may
    /// reach; with none, a fast flick still opens the picker, which lists AirDrop.
    public static func classify(samples: [FlickSample], sensitivity: FlickSensitivity, peers: Int) -> FlickOutcome {
        let boxed = samples.map { FlickPointBox(time: $0.time, x: Double($0.point.x), y: Double($0.point.y)) }
        switch FlingFlickBox.classify(samples: boxed, threshold: Double(sensitivity.threshold), peers: peers) {
        case .drop: return .drop
        case .picker: return .picker
        case .send(let peerIndex): return .send(peerIndex: peerIndex)
        }
    }
}
