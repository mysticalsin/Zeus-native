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
        case .low: return 1800
        case .normal: return 1200
        case .high: return 800
        }
    }
}

public enum FlickOutcome: Equatable, Sendable {
    case drop
    case send(peerIndex: Int)
    case picker
}

public enum FlingFlick {
    public static let window: TimeInterval = 0.08

    /// Points are in screen space with y growing downward, so up is negative y. `peers` counts the Macs a flick may
    /// reach; with none, a fast flick still opens the picker, which lists AirDrop.
    public static func classify(samples: [FlickSample], sensitivity: FlickSensitivity, peers: Int) -> FlickOutcome {
        guard let last = samples.last else { return .drop }
        let recent = samples.filter { $0.time >= last.time - window - 1e-9 }
        guard let first = recent.first, last.time > first.time else { return .drop }
        let dt = CGFloat(last.time - first.time)
        let dx = last.point.x - first.point.x, dy = last.point.y - first.point.y
        guard hypot(dx, dy) / dt >= sensitivity.threshold else { return .drop }
        if peers <= 0 { return .picker }
        if peers == 1 { return .send(peerIndex: 0) }
        if abs(dy) > abs(dx) { return dy < 0 ? .picker : .drop }
        return .send(peerIndex: dx < 0 ? 0 : peers - 1)
    }
}
