import Foundation

/// A watchdog may replace one stalled mute scan, but cannot spawn unbounded CoreAudio workers.
/// Rejected refreshes are not queued. If both reads stall, evidence expires and admission stays
/// fail closed until a slot actually returns; cancelling a synchronous OS read is not assumed.
public final class ScribeMuteReadScheduler: @unchecked Sendable {
    static let maximumConcurrentReads = 2
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "zeus.scribe.mute", qos: .userInitiated, attributes: .concurrent)
    private var inFlight: [UUID: TimeInterval] = [:]

    public init() {}

    var activeReadCount: Int { lock.withLock { inFlight.count } }

    @discardableResult
    public func schedule(now: TimeInterval, evidenceTakenAt: TimeInterval?, interval: TimeInterval,
                         watchdog: TimeInterval, read: @escaping @Sendable () -> Void) -> Bool {
        let token = lock.withLock { () -> UUID? in
            guard now.isFinite, interval.isFinite, interval > 0, watchdog.isFinite, watchdog > 0,
                  evidenceTakenAt?.isFinite != false,
                  inFlight.count < Self.maximumConcurrentReads,
                  ScribeMuteRefreshPolicy.shouldStart(now: now, evidenceTakenAt: evidenceTakenAt,
                                                     inFlightSince: inFlight.values.max(),
                                                     interval: interval, watchdog: watchdog) else { return nil }
            let token = UUID()
            inFlight[token] = now
            return token
        }
        guard let token else { return false }
        queue.async { [self] in
            defer { _ = lock.withLock { inFlight.removeValue(forKey: token) } }
            read()
        }
        return true
    }
}
