import Foundation

/// Something an agent did that Tony may have missed while he was away.
public struct RecapEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case finished, failed, waiting }
    public var kind: Kind
    /// The agent session (or the approval, when it has no session): what "Open" jumps to.
    public var id: String
    public var agent: String
    public var project: String
    public var detail: String?
    public var date: Date

    public init(kind: Kind, id: String, agent: String, project: String, detail: String? = nil, date: Date) {
        self.kind = kind; self.id = id; self.agent = agent; self.project = project; self.detail = detail; self.date = date
    }
}

/// Notices when Tony comes back from being away. Fed the system idle time (seconds since the last key or mouse
/// event) on every poll; it also catches a sleep in between, when the idle counter restarts.
public struct AwayTracker: Sendable {
    public static let minimumAway: TimeInterval = 10 * 60

    public struct Return: Equatable, Sendable {
        /// When his last input before leaving happened.
        public var awayStart: Date
        public var awaySeconds: TimeInterval
    }

    private var last: (idle: TimeInterval, at: Date)?
    public init() {}

    /// Returns a value on the poll where input resumes after at least `minimumAway` of none.
    public mutating func update(idle: TimeInterval, now: Date, minimumAway: TimeInterval = AwayTracker.minimumAway) -> Return? {
        defer { last = (idle, now) }
        guard let last else { return nil }
        // Idle grows with the clock. If it grew by less than the clock did, input happened in between.
        let expected = last.idle + now.timeIntervalSince(last.at)
        guard idle < expected - 2 else { return nil }
        let awayStart = last.at.addingTimeInterval(-last.idle)
        let awaySeconds = now.addingTimeInterval(-idle).timeIntervalSince(awayStart)
        guard awaySeconds >= minimumAway else { return nil }
        return Return(awayStart: awayStart, awaySeconds: awaySeconds)
    }
}

/// What the "Welcome back" card says.
public struct WelcomeRecap: Equatable, Sendable {
    public var awaySeconds: TimeInterval
    public var finished: [RecapEvent]
    public var failed: [RecapEvent]
    public var waiting: [RecapEvent]

    public init(awaySeconds: TimeInterval, finished: [RecapEvent], failed: [RecapEvent], waiting: [RecapEvent]) {
        self.awaySeconds = awaySeconds; self.finished = finished; self.failed = failed; self.waiting = waiting
    }

    public var isEmpty: Bool { finished.isEmpty && failed.isEmpty && waiting.isEmpty }
    public var all: [RecapEvent] { failed + waiting + finished }

    /// The recap for a return, or nil when he was not gone long enough or nothing happened.
    /// Only events since he left count; of several events for one session the latest wins; a "waiting" that
    /// has since been answered (not in `stillWaiting`) is dropped.
    public static func make(events: [RecapEvent], awayStart: Date, awaySeconds: TimeInterval, stillWaiting: Set<String>,
                            minimumAway: TimeInterval = AwayTracker.minimumAway) -> WelcomeRecap? {
        guard awaySeconds >= minimumAway else { return nil }
        var latest: [String: RecapEvent] = [:]
        for event in events.sorted(by: { $0.date < $1.date }) where event.date >= awayStart {
            latest[event.id] = event
        }
        let kept = latest.values.filter { $0.kind != .waiting || stillWaiting.contains($0.id) }.sorted { $0.date > $1.date }
        let recap = WelcomeRecap(awaySeconds: awaySeconds,
                                 finished: kept.filter { $0.kind == .finished },
                                 failed: kept.filter { $0.kind == .failed },
                                 waiting: kept.filter { $0.kind == .waiting })
        return recap.isEmpty ? nil : recap
    }

    /// "2 finished, 1 failed, 1 waiting for you".
    public var summary: String {
        var parts: [String] = []
        if !finished.isEmpty { parts.append("\(finished.count) finished") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        if !waiting.isEmpty { parts.append("\(waiting.count) waiting for you") }
        return parts.joined(separator: ", ")
    }

    /// "Away 23 min", "Away 2 h 5 min".
    public var awayText: String {
        let minutes = Int(awaySeconds / 60)
        return minutes >= 60 ? "Away \(minutes / 60) h \(minutes % 60) min" : "Away \(minutes) min"
    }
}

/// A session as the recap sees it.
public struct RecapSession: Equatable, Sendable {
    public var id: String
    public var agent: String
    public var project: String
    public var status: AgentRunState
    public var reason: String?
    public init(id: String, agent: String, project: String, status: AgentRunState, reason: String? = nil) {
        self.id = id; self.agent = agent; self.project = project; self.status = status; self.reason = reason
    }
}

/// Turns changes in session status into recap events, and keeps the last few.
public struct RecapLog: Sendable {
    public private(set) var events: [RecapEvent] = []
    private var seen: [String: AgentRunState] = [:]
    private var approvalSeen: String?
    public var limit = 200

    public init() {}

    /// Call on every poll with the current sessions and the pending approval (id, session id, agent, project), if any.
    public mutating func observe(sessions: [RecapSession], approval: (id: String, session: String?, agent: String, project: String, tool: String)?, now: Date) {
        for session in sessions {
            let before = seen[session.id]
            seen[session.id] = session.status
            guard before != session.status else { continue }
            switch session.status {
            case .done: add(.init(kind: .finished, id: session.id, agent: session.agent, project: session.project, date: now))
            case .failed: add(.init(kind: .failed, id: session.id, agent: session.agent, project: session.project, detail: session.reason, date: now))
            case .needsYou: add(.init(kind: .waiting, id: session.id, agent: session.agent, project: session.project, date: now))
            default: break
            }
        }
        let gone = Set(seen.keys).subtracting(sessions.map(\.id))
        for id in gone { seen[id] = nil }
        if let approval, approvalSeen != approval.id {
            add(.init(kind: .waiting, id: approval.session ?? approval.id, agent: approval.agent, project: approval.project, detail: approval.tool, date: now))
        }
        approvalSeen = approval?.id
    }

    /// The sessions (and approval) that are waiting for him right now.
    public static func waitingNow(sessions: [RecapSession], approvalID: String?) -> Set<String> {
        Set(sessions.filter { $0.status == .needsYou }.map(\.id)).union(approvalID.map { [$0] } ?? [])
    }

    private mutating func add(_ event: RecapEvent) {
        events.append(event)
        if events.count > limit { events.removeFirst(events.count - limit) }
    }
}
