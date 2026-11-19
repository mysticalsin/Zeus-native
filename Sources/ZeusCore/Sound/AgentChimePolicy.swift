import Foundation

/// Decides which agent events earn a chime, so short automated turns and chatty
/// background sessions do not ding over and over. Pure: the caller feeds it session
/// states and the approval card, with timestamps, and plays whatever cue comes back.
public struct AgentChimePolicy: Sendable {
    public enum Cue: Equatable, Sendable { case start, done, approval, answer }

    /// A turn shorter than this finishes silently.
    public static let minWorkSeconds: TimeInterval = 20
    /// At most one agent chime in this window, across every session.
    public static let coalesceSeconds: TimeInterval = 3
    /// Clearing an approval chimes only if the card was up at least this long.
    public static let minApprovalSeconds: TimeInterval = 2

    private var stretchStart: [String: Date] = [:]
    private var lastState: [String: AgentRunState] = [:]
    private var approvalSince: Date?
    private var lastChime: Date?

    public init() {}

    /// Call once per session per tick with its current state.
    public mutating func session(_ id: String, status: AgentRunState, at now: Date, startEnabled: Bool) -> Cue? {
        let previous = lastState[id]
        lastState[id] = status
        let inStretch = previous == .working || previous == .needsYou || previous == .stalled
        switch status {
        case .working:
            guard previous != .working else { return nil }
            if !inStretch {
                stretchStart[id] = now
                return startEnabled ? chime(.start, at: now) : nil
            }
            return nil
        case .needsYou, .stalled:
            if stretchStart[id] == nil { stretchStart[id] = now }
            return nil
        case .done:
            defer { stretchStart[id] = nil }
            guard inStretch, let began = stretchStart[id], now.timeIntervalSince(began) >= Self.minWorkSeconds else { return nil }
            return chime(.done, at: now)
        case .idle, .failed:
            stretchStart[id] = nil
            return nil
        }
    }

    /// Call once per tick with whether an approval card is up.
    public mutating func approval(visible: Bool, at now: Date) -> Cue? {
        if visible {
            guard approvalSince == nil else { return nil }
            approvalSince = now
            return chime(.approval, at: now)
        }
        guard let since = approvalSince else { return nil }
        approvalSince = nil
        return now.timeIntervalSince(since) >= Self.minApprovalSeconds ? chime(.answer, at: now) : nil
    }

    /// Drops state for sessions that no longer exist.
    public mutating func forget(keeping alive: Set<String>) {
        stretchStart = stretchStart.filter { alive.contains($0.key) }
        lastState = lastState.filter { alive.contains($0.key) }
    }

    private mutating func chime(_ cue: Cue, at now: Date) -> Cue? {
        if let last = lastChime, now.timeIntervalSince(last) < Self.coalesceSeconds { return nil }
        lastChime = now
        return cue
    }
}
