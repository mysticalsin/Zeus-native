// Adapted from Glance (MIT, Copyright (c) 2026 Jonathan Zhou): FaceLabController.swift, CameraManager.swift.
import Foundation

/// Decides which camera frames get analyzed: at most one every half second, and never two at once. The camera
/// delegate asks before it converts a frame, so a frame in between costs a comparison and nothing else. No clock
/// inside: the frame's monotonic time arrives with every call.
public struct PresenceSampler: Equatable, Sendable {
    /// Seconds between the starts of two analyses.
    public static let interval: Double = 0.5

    private var lastStart: Double?
    private var inFlight = false

    public init() {}

    /// True while an analysis has started and `analysisFinished` has not been called.
    public var isAnalyzing: Bool { inFlight }

    /// True when this frame should be analyzed, which also marks an analysis as running. False drops the frame.
    /// A time that is not a number drops it. A time earlier than the last start (a capture session that restarted
    /// its clock) is taken, so the sampler can never wait on a clock that moved back.
    public mutating func shouldAnalyze(at uptime: Double) -> Bool {
        guard uptime.isFinite, !inFlight else { return false }
        if let lastStart, uptime >= lastStart, uptime - lastStart < Self.interval { return false }
        lastStart = uptime
        inFlight = true
        return true
    }

    /// The running analysis ended, with a result or not. Safe to call with nothing running.
    public mutating func analysisFinished() {
        inFlight = false
    }

    /// Forgets the flight and the clock, for a camera stop or a new watch.
    public mutating func reset() {
        lastStart = nil
        inFlight = false
    }
}
