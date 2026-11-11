import Foundation

/// The microphone's application input boundary. The audio callback obtains a nonblocking permit before
/// reading sample memory or writing the application ring. Known mute/unknown/stale evidence never copies.
/// This cannot observe an OS mute transition before the OS reports it, or prevent OS-owned audio buffers.
public final class ScribeMicrophoneIngress: @unchecked Sendable {
    public struct Report: Equatable, Sendable {
        public let state: ScribeMuteState
        public let withheldSeconds: TimeInterval
    }

    private let lock = NSLock()
    private let timeToLive: TimeInterval
    private var session: ScribeSessionID?
    private var acknowledgedAt: TimeInterval?
    private var state: ScribeMuteState = .unknown
    private var readStart: TimeInterval = -.infinity
    private var readEnd: TimeInterval = .infinity
    private var withheldSeconds: TimeInterval = 0
    private var withheldState: ScribeMuteState?

    public init(timeToLive: TimeInterval = 1.5) { self.timeToLive = timeToLive }

    public func begin(session: ScribeSessionID) {
        lock.withLock {
            self.session = session
            acknowledgedAt = nil
            withheldSeconds = 0
            withheldState = nil
        }
    }

    @discardableResult
    public func acknowledge(session: ScribeSessionID, at time: TimeInterval) -> Bool {
        lock.withLock {
            guard self.session == session, time.isFinite else { return false }
            acknowledgedAt = time
            return true
        }
    }

    public func revoke(session: ScribeSessionID) {
        lock.withLock {
            guard self.session == session else { return }
            self.session = nil
            acknowledgedAt = nil
        }
    }

    /// Another app using the microphone is not part of the evidence: it never withholds the microphone,
    /// so nothing here can stay set after that app lets go of it.
    public func record(state: ScribeMuteState, readStart: TimeInterval, readEnd: TimeInterval) {
        lock.withLock {
            guard readStart.isFinite, readEnd.isFinite, readEnd >= readStart else {
                self.state = .unknown
                return
            }
            guard readStart >= self.readStart else { return }
            self.state = state
            self.readStart = readStart
            self.readEnd = readEnd
        }
    }

    public func currentState(now: TimeInterval) -> ScribeMuteState {
        lock.withLock { effectiveState(now: now) }
    }

    /// `copy` must be synchronous/nonblocking. Holding the permit through the write gives revocation a
    /// defined boundary: after revoke/record returns, no earlier permitted copy can still be running.
    /// A contended callback is dropped immediately; it never waits on a scan, a writer, or another callback.
    @discardableResult
    public func admit(session: ScribeSessionID, start: TimeInterval?, duration: TimeInterval,
                      now: TimeInterval, copy: () -> Bool) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        let validTiming = duration.isFinite && duration > 0 && now.isFinite
        guard self.session == session, let acknowledgedAt, let start,
              validTiming, start.isFinite, start >= acknowledgedAt,
              start + duration <= now,
              effectiveState(now: now) == .unmuted,
              start >= readEnd, start + duration <= readStart + timeToLive else {
            if self.session == session, acknowledgedAt != nil, validTiming {
                withheldSeconds += duration
                let rejectedState: ScribeMuteState = effectiveState(now: now) == .muted ? .muted : .unknown
                withheldState = withheldState == .unknown || rejectedState == .unknown ? .unknown : .muted
            }
            return false
        }
        return copy()
    }

    public func takeReport(now: TimeInterval) -> Report {
        lock.withLock {
            defer { withheldSeconds = 0; withheldState = nil }
            return Report(state: withheldState ?? effectiveState(now: now), withheldSeconds: withheldSeconds)
        }
    }

    private func effectiveState(now: TimeInterval) -> ScribeMuteState {
        guard now.isFinite, timeToLive.isFinite, timeToLive > 0,
              now >= readEnd, now <= readStart + timeToLive else { return .unknown }
        return state
    }
}
