import Foundation

/// ScreenCaptureKit timestamps use the host clock, not a zero-based movie timeline.
/// The first usable video frame establishes the origin for both the writer and cursor log.
public struct RecordlyCaptureTimeline: Sendable {
    public enum Admission: Equatable, Sendable {
        case drop
        case startSession
        case append
    }

    public private(set) var origin: Double?

    public init() {}

    /// Call only for an input that is ready and, for video, a complete frame.
    /// Audio arriving before the first video frame cannot establish a movie's origin.
    public mutating func admit(presentationTime: Double, isVideo: Bool) -> Admission {
        guard presentationTime.isFinite, presentationTime >= 0 else { return .drop }
        if let origin { return presentationTime >= origin ? .append : .drop }
        guard isVideo else { return .drop }
        origin = presentationTime
        return .startSession
    }

    /// Cursor events share the sample clock; wall-clock adjustments cannot move them in the movie.
    public func elapsed(at hostTime: Double) -> Double? {
        guard let origin, hostTime.isFinite, hostTime >= origin else { return nil }
        return hostTime - origin
    }
}
