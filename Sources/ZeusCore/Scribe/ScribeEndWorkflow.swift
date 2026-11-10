import Foundation

/// A positive OS termination event is useful only for the exact app instance bound to this session.
/// PID alone is insufficient because macOS can reuse it after an app exits.
public struct ScribeCallProcessIdentity: Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String
    public let launchedAt: TimeInterval

    public init(pid: Int32, bundleID: String, launchedAt: TimeInterval) {
        self.pid = pid
        self.bundleID = bundleID
        self.launchedAt = launchedAt
    }

    fileprivate var isValid: Bool {
        pid > 0 && !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && launchedAt.isFinite && launchedAt >= 0
    }
}

/// End confirmation for a recording. Only an explicit Stop or a positively observed termination
/// of its bound call-app instance can arm it. Microphone inactivity and calendar end times are
/// deliberately not inputs. The caller still waits for the capture provider's stopped event.
public struct ScribeEndWorkflow: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case requestedByUser
        case boundCallAppClosed
    }

    public static let grace: TimeInterval = 9
    public private(set) var session: ScribeSessionID?
    public private(set) var boundCall: ScribeCallProcessIdentity?
    public private(set) var reason: Reason?
    public private(set) var deadline: TimeInterval?
    public private(set) var stopRequested = false
    private var observedBoundTermination = false

    public init() {}

    public mutating func begin(session: ScribeSessionID, boundCall: ScribeCallProcessIdentity?) {
        self.session = session
        self.boundCall = boundCall?.isValid == true ? boundCall : nil
        reason = nil
        deadline = nil
        stopRequested = false
        observedBoundTermination = false
    }

    @discardableResult
    public mutating func requestEnd(session: ScribeSessionID, now: TimeInterval) -> Bool {
        arm(session: session, reason: .requestedByUser, now: now)
    }

    @discardableResult
    public mutating func applicationTerminated(_ identity: ScribeCallProcessIdentity,
                                               session: ScribeSessionID, now: TimeInterval) -> Bool {
        guard self.session == session, !stopRequested, identity.isValid,
              identity == boundCall, !observedBoundTermination,
              Self.validDeadline(now) != nil else { return false }
        // Consume the observed instance even when an explicit Stop already has a countdown.
        // Keep recording must not be defeated by duplicate delivery of that old termination.
        observedBoundTermination = true
        return arm(session: session, reason: .boundCallAppClosed, now: now)
    }

    @discardableResult
    public mutating func keepRecording(session: ScribeSessionID) -> Bool {
        guard self.session == session, !stopRequested, deadline != nil else { return false }
        deadline = nil
        reason = nil
        return true
    }

    /// Returns true exactly once when this workflow requests the provider to stop.
    @discardableResult
    public mutating func stopIfDue(session: ScribeSessionID, now: TimeInterval) -> Bool {
        guard self.session == session, !stopRequested, let deadline,
              now.isFinite, now >= 0, now >= deadline else { return false }
        stopRequested = true
        return true
    }

    @discardableResult
    public mutating func endNow(session: ScribeSessionID) -> Bool {
        guard self.session == session, !stopRequested, deadline != nil else { return false }
        stopRequested = true
        return true
    }

    public func remaining(now: TimeInterval) -> TimeInterval? {
        guard !stopRequested, let deadline, now.isFinite, now >= 0 else { return nil }
        return max(0, min(Self.grace, deadline - now))
    }

    private mutating func arm(session: ScribeSessionID, reason: Reason, now: TimeInterval) -> Bool {
        guard self.session == session, !stopRequested, deadline == nil,
              let deadline = Self.validDeadline(now) else { return false }
        self.deadline = deadline
        self.reason = reason
        return true
    }

    private static func validDeadline(_ now: TimeInterval) -> TimeInterval? {
        guard now.isFinite, now >= 0 else { return nil }
        let deadline = now + grace
        return deadline.isFinite && deadline > now ? deadline : nil
    }
}
