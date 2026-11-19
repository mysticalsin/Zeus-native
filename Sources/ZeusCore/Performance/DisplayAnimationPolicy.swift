import Foundation

/// Display-link preferences are requests, never a claim that the compositor delivered this rate.
public enum DisplayAnimationPolicy {
    public static let maximumRequestedFramesPerSecond = 240

    /// An unknown display does not acquire an invented refresh rate. The host waits for a screen.
    public static func requestedFramesPerSecond(screenMaximum: Int, preferred: Int = 240) -> Int {
        guard screenMaximum > 0, preferred > 0 else { return 0 }
        return min(screenMaximum, preferred, maximumRequestedFramesPerSecond)
    }

    public static func mayPublish(appeared: Bool, paused: Bool, reduceMotion: Bool,
                                  attached: Bool, hidden: Bool, windowVisible: Bool,
                                  miniaturized: Bool, windowAlpha: Double) -> Bool {
        appeared && !paused && !reduceMotion && attached && !hidden && windowVisible && !miniaturized
            && windowAlpha.isFinite && windowAlpha > 0.01
    }

    /// Producers timestamp phases with Date. Resample that same wall-clock domain for every frame;
    /// a permanently anchored monotonic conversion would hide new phases after a clock correction.
    /// Only the short lead to the next display target is borrowed from the monotonic display link.
    public static func presentationTime(wallNow: Double, targetTimestamp: Double, deliveredAt: Double) -> Double? {
        guard wallNow.isFinite, targetTimestamp.isFinite, deliveredAt.isFinite else { return nil }
        let lead = targetTimestamp - deliveredAt
        guard lead.isFinite else { return nil }
        let result = wallNow + min(0.1, max(0, lead))
        return result.isFinite ? result : nil
    }
}

/// A finite animation's lifetime. Nil means continuous; invalid deadlines fail closed.
/// It is advanced only by real display callbacks or host lifecycle events, never by a poller.
public struct DisplayAnimationDeadline: Equatable, Sendable {
    public private(set) var until: Double?
    public private(set) var reached = false

    public init() {}

    public mutating func configure(until: Double?, now: Double) {
        self.until = until
        reached = !now.isFinite || until.map { !$0.isFinite || $0 <= now } == true
    }

    /// True exactly once when an active finite interval reaches its final frame.
    @discardableResult public mutating func finishIfNeeded(at presentationTime: Double) -> Bool {
        guard !reached, let until else { return false }
        guard !presentationTime.isFinite || presentationTime >= until else { return false }
        reached = true
        return true
    }

    /// A predicted final display timestamp can be just ahead of wall time. Do not move the final
    /// rendered frame backward when the link stops; a later ordinary view update samples fresh now.
    public func settledTime(now: Double, lastFrame: Double) -> Double {
        guard reached else { return now }
        return max(now.isFinite ? now : 0, lastFrame.isFinite ? lastFrame : 0,
                   until.flatMap { $0.isFinite ? $0 : nil } ?? 0)
    }
}

/// Bounded, allocation-free callback diagnostics. These measure the callback delivery/publication
/// path only: SwiftUI rendering, compositor presentation and GPU completion are not measured here.
public struct DisplayCallbackMetrics: Equatable, Sendable {
    public private(set) var callbackCount: UInt64 = 0
    public private(set) var deliveredAfterTargetCount: UInt64 = 0
    public private(set) var maximumLateness: Double = 0
    public private(set) var maximumCallbackWork: Double = 0
    public private(set) var firstDelivery: Double?
    public private(set) var lastDelivery: Double?
    public private(set) var lastTarget: Double?

    public init() {}

    public var measuredCallbackFrequency: Double? {
        guard callbackCount > 1, let firstDelivery, let lastDelivery, lastDelivery > firstDelivery else { return nil }
        return Double(callbackCount - 1) / (lastDelivery - firstDelivery)
    }

    /// A duplicated/out-of-order display target never schedules another SwiftUI publication.
    @discardableResult
    public mutating func record(target: Double, delivered: Double) -> Bool {
        guard target.isFinite, delivered.isFinite, target >= 0, delivered >= 0,
              lastTarget.map({ target > $0 }) ?? true,
              lastDelivery.map({ delivered >= $0 }) ?? true else { return false }
        if firstDelivery == nil { firstDelivery = delivered }
        lastDelivery = delivered
        lastTarget = target
        callbackCount &+= 1
        let lateness = max(0, delivered - target)
        maximumLateness = max(maximumLateness, lateness)
        // Ignore sub-100µs sampling noise. This still is callback lateness, not a dropped GPU frame.
        if lateness > 0.0001 { deliveredAfterTargetCount &+= 1 }
        return true
    }

    public mutating func recordCallbackWork(_ duration: Double) {
        guard duration.isFinite, duration >= 0 else { return }
        maximumCallbackWork = max(maximumCallbackWork, duration)
    }
}
