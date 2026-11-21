import Foundation

/// The revision 3 decision machine. A state and an event go in, and the next state comes out.
/// The clock is the `at` on an event, in milliseconds. Nothing here reads the wall clock,
/// draws a button, or runs an action before the undo window has passed.

public enum HubRevision3Decision {
    public static func step(_ state: HubRevision3State, _ event: HubRevision3Event) -> HubRevision3Outcome {
        switch event {
        case .request(let request):
            return enqueue(state, request)
        case .advance(let now):
            return passTime(state, to: now)
        case .key(let key, let command):
            return press(state, key, command: command)
        case .pause(let reason, let active):
            return pause(state, reason, active: active)
        case .holdBegan(let action, let at):
            return beginHold(state, action, at: at)
        case .holdReleased(let at):
            return endHold(state, at: at)
        case .replaceNote(let text):
            return replaceNote(state, text)
        }
    }

    private static func enqueue(_ state: HubRevision3State, _ request: HubRevision3Request) -> HubRevision3Outcome {
        guard isBound(request) else { return .unchanged(state) }
        if state.showing?.id == request.id || state.waiting.contains(where: { $0.id == request.id }) {
            return .unchanged(state)
        }
        var next = state
        if next.showing == nil, next.pending == nil, next.waiting.isEmpty {
            next.showing = request
            next.remainingMilliseconds = HubRevision3Timing.countdownMilliseconds
            next.note = ""
            next.holdAction = nil
            next.holdBeganAt = nil
            return HubRevision3Outcome(
                state: next,
                announcement: HubRevision3Speech.revealed(tier: request.tier, waiting: 0))
        }
        next.waiting.append(request)
        return HubRevision3Outcome(state: next, announcement: HubRevision3Speech.queue(next.waiting.count))
    }

    private static func press(_ state: HubRevision3State, _ key: HubDecisionKey, command: Bool) -> HubRevision3Outcome {
        if command { return .unchanged(state) }
        if state.pending != nil {
            guard key == .undo else { return .unchanged(state) }
            return undo(state)
        }
        guard let showing = state.showing else { return .unchanged(state) }
        if key == .shiftEscape {
            let ids = [showing.id] + state.waiting.map(\.id)
            return begin(
                state,
                action: .deny,
                note: nil,
                ids: ids,
                deniesAllQueued: true,
                holdMilliseconds: nil,
                at: state.clock,
                fromCountdown: false,
                tier: showing.tier)
        }
        guard let action = key.action else { return .unchanged(state) }
        if action.isApproval, showing.tier == .destructive { return .unchanged(state) }
        if action == .denyWithNote {
            guard state.note.count <= HubRevision3Timing.noteCharacterLimit else { return .unchanged(state) }
            return begin(
                state,
                action: .denyWithNote,
                note: state.note,
                ids: [showing.id],
                deniesAllQueued: false,
                holdMilliseconds: nil,
                at: state.clock,
                fromCountdown: false,
                tier: showing.tier)
        }
        return begin(
            state,
            action: action,
            note: nil,
            ids: [showing.id],
            deniesAllQueued: false,
            holdMilliseconds: nil,
            at: state.clock,
            fromCountdown: false,
            tier: showing.tier)
    }

    private static func pause(
        _ state: HubRevision3State,
        _ reason: HubCountdownPause,
        active: Bool
    ) -> HubRevision3Outcome {
        guard state.showing != nil || state.pending != nil else { return .unchanged(state) }
        var next = state
        if active {
            next.pauses.insert(reason)
        } else {
            next.pauses.remove(reason)
        }
        guard next.pauses != state.pauses else { return .unchanged(state) }
        let wasPaused = !state.pauses.isEmpty
        let nowPaused = !next.pauses.isEmpty
        var announcement: String?
        if state.showing != nil, state.pending == nil {
            if !wasPaused, nowPaused { announcement = HubRevision3Speech.paused }
            if wasPaused, !nowPaused { announcement = HubRevision3Speech.resumed }
        }
        return HubRevision3Outcome(state: next, announcement: announcement)
    }

    private static func beginHold(
        _ state: HubRevision3State,
        _ action: HubDecisionAction,
        at: Int
    ) -> HubRevision3Outcome {
        guard action.isApproval else { return .unchanged(state) }
        guard state.pending == nil, state.showing != nil, state.holdBeganAt == nil else { return .unchanged(state) }
        guard at >= state.clock else { return .unchanged(state) }
        let advanced = passTime(state, to: at)
        guard advanced.state.pending == nil, advanced.state.showing != nil, advanced.state.holdBeganAt == nil else {
            return advanced
        }
        var next = advanced.state
        next.holdAction = action
        next.holdBeganAt = at
        next.clock = at
        return HubRevision3Outcome(state: next, announcement: advanced.announcement)
    }

    private static func endHold(_ state: HubRevision3State, at: Int) -> HubRevision3Outcome {
        guard let began = state.holdBeganAt, let action = state.holdAction else { return .unchanged(state) }
        guard at >= began, at >= state.clock else { return .unchanged(state) }
        let elapsed = at - began
        let advanced = passTime(state, to: at)
        if advanced.state.pending != nil || advanced.state.showing == nil {
            var next = advanced.state
            next.holdAction = nil
            next.holdBeganAt = nil
            return HubRevision3Outcome(state: next, announcement: advanced.announcement)
        }
        guard let showing = advanced.state.showing else { return advanced }
        let required = showing.tier == .destructive ? HubRevision3Timing.destructiveHoldMilliseconds : 0
        guard elapsed >= required else {
            var next = advanced.state
            next.holdAction = nil
            next.holdBeganAt = nil
            return HubRevision3Outcome(state: next, announcement: advanced.announcement)
        }
        return begin(
            advanced.state,
            action: action,
            note: nil,
            ids: [showing.id],
            deniesAllQueued: false,
            holdMilliseconds: elapsed,
            at: at,
            fromCountdown: false,
            tier: showing.tier)
    }

    private static func replaceNote(_ state: HubRevision3State, _ text: String) -> HubRevision3Outcome {
        guard state.decisionShowing else { return .unchanged(state) }
        guard text.count <= HubRevision3Timing.noteCharacterLimit else { return .unchanged(state) }
        var next = state
        next.note = text
        return HubRevision3Outcome(state: next)
    }

    private static func undo(_ state: HubRevision3State) -> HubRevision3Outcome {
        guard let pending = state.pending else { return .unchanged(state) }
        var next = state
        next.pending = nil
        next.holdAction = nil
        next.holdBeganAt = nil
        if pending.fromCountdown, next.remainingMilliseconds == 0, next.showing != nil {
            next.remainingMilliseconds = HubRevision3Timing.countdownMilliseconds
        }
        return HubRevision3Outcome(state: next, announcement: HubRevision3Speech.undone)
    }

    private static func passTime(_ state: HubRevision3State, to now: Int) -> HubRevision3Outcome {
        guard now > state.clock else { return .unchanged(state) }
        var state = state
        var cursor = state.clock
        var announcement: String?
        while cursor < now {
            if let pending = state.pending {
                if pending.undoUntil > now {
                    state.clock = now
                    return HubRevision3Outcome(state: state, announcement: announcement)
                }
                let executed = execute(state)
                state = executed.state
                announcement = executed.announcement
                cursor = pending.undoUntil
                continue
            }
            if state.showing != nil, state.pauses.isEmpty {
                let remaining = max(state.remainingMilliseconds, 0)
                let hit = cursor + remaining
                if hit > now {
                    state.remainingMilliseconds = remaining - (now - cursor)
                    state.clock = now
                    return HubRevision3Outcome(state: state, announcement: announcement)
                }
                state.remainingMilliseconds = 0
                state.clock = hit
                guard let showing = state.showing else {
                    state.clock = now
                    return HubRevision3Outcome(state: state, announcement: announcement)
                }
                let denied = begin(
                    state,
                    action: .deny,
                    note: nil,
                    ids: [showing.id],
                    deniesAllQueued: false,
                    holdMilliseconds: nil,
                    at: hit,
                    fromCountdown: true,
                    tier: showing.tier)
                state = denied.state
                announcement = denied.announcement
                cursor = hit
                continue
            }
            state.clock = now
            return HubRevision3Outcome(state: state, announcement: announcement)
        }
        state.clock = max(state.clock, now)
        return HubRevision3Outcome(state: state, announcement: announcement)
    }

    private static func execute(_ state: HubRevision3State) -> HubRevision3Outcome {
        guard let pending = state.pending else { return .unchanged(state) }
        var next = state
        next.executed.append(HubRevision3Execution(
            action: pending.action,
            note: pending.note,
            requestIDs: pending.requestIDs,
            atMilliseconds: pending.undoUntil,
            deniesAllQueued: pending.deniesAllQueued,
            holdMilliseconds: pending.holdMilliseconds,
            fromCountdown: pending.fromCountdown,
            tier: pending.tier))
        next.pending = nil
        let closed = Set(pending.requestIDs)
        if let showing = next.showing, closed.contains(showing.id) {
            next.showing = nil
        }
        next.waiting.removeAll { closed.contains($0.id) }
        next.holdAction = nil
        next.holdBeganAt = nil
        next.note = ""
        var announcement: String?
        if next.showing == nil, !next.waiting.isEmpty {
            let promoted = next.waiting.removeFirst()
            next.showing = promoted
            next.remainingMilliseconds = HubRevision3Timing.countdownMilliseconds
            announcement = HubRevision3Speech.revealed(tier: promoted.tier, waiting: next.waiting.count)
        } else if next.showing == nil {
            next.remainingMilliseconds = 0
        }
        next.clock = pending.undoUntil
        return HubRevision3Outcome(state: next, announcement: announcement)
    }

    private static func begin(
        _ state: HubRevision3State,
        action: HubDecisionAction,
        note: String?,
        ids: [String],
        deniesAllQueued: Bool,
        holdMilliseconds: Int?,
        at: Int,
        fromCountdown: Bool,
        tier: HubRiskTier?
    ) -> HubRevision3Outcome {
        var next = state
        next.pending = HubRevision3Pending(
            action: action,
            note: note,
            requestIDs: ids,
            deniesAllQueued: deniesAllQueued,
            undoUntil: at + HubRevision3Timing.undoMilliseconds,
            holdMilliseconds: holdMilliseconds,
            fromCountdown: fromCountdown,
            tier: tier)
        next.holdAction = nil
        next.holdBeganAt = nil
        next.clock = at
        return HubRevision3Outcome(
            state: next,
            announcement: HubRevision3Speech.pending(action, deniesAllQueued: deniesAllQueued))
    }

    private static func isBound(_ request: HubRevision3Request) -> Bool {
        !request.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !request.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum HubRevision3Speech {
    public static func revealed(tier: HubRiskTier, waiting: Int) -> String {
        "\(tier.title). \(queue(waiting))"
    }

    public static func queue(_ waiting: Int) -> String {
        switch waiting {
        case 0: "Nothing waiting."
        case 1: "1 waiting."
        default: "\(waiting) waiting."
        }
    }

    public static func pending(_ action: HubDecisionAction, deniesAllQueued: Bool) -> String {
        if deniesAllQueued { return "Deny all queued. Undo." }
        return "\(action.title). Undo."
    }

    public static let undone = "Undone."
    public static let paused = "Countdown paused."
    public static let resumed = "Countdown resumed."

    /// Whole seconds, always a denial. Pausing keeps the sentence and says that it is paused.
    public static func countdown(remainingMilliseconds: Int, paused: Bool) -> String {
        let seconds = max(remainingMilliseconds, 0) / 1_000
        let body = "\(seconds) s left, then it's denied."
        return paused ? "Countdown paused. \(body)" : body
    }
}

public struct HubRevision3Request: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sessionID: String
    public var tier: HubRiskTier

    public init(id: String, sessionID: String, tier: HubRiskTier) {
        self.id = id
        self.sessionID = sessionID
        self.tier = tier
    }
}

public struct HubRevision3Pending: Equatable, Sendable {
    public var action: HubDecisionAction
    public var note: String?
    public var requestIDs: [String]
    public var deniesAllQueued: Bool
    public var undoUntil: Int
    public var holdMilliseconds: Int?
    public var fromCountdown: Bool
    public var tier: HubRiskTier?

    public init(
        action: HubDecisionAction,
        note: String?,
        requestIDs: [String],
        deniesAllQueued: Bool,
        undoUntil: Int,
        holdMilliseconds: Int?,
        fromCountdown: Bool,
        tier: HubRiskTier?
    ) {
        self.action = action
        self.note = note
        self.requestIDs = requestIDs
        self.deniesAllQueued = deniesAllQueued
        self.undoUntil = undoUntil
        self.holdMilliseconds = holdMilliseconds
        self.fromCountdown = fromCountdown
        self.tier = tier
    }
}

public struct HubRevision3Execution: Equatable, Sendable {
    public var action: HubDecisionAction
    public var note: String?
    public var requestIDs: [String]
    public var atMilliseconds: Int
    public var deniesAllQueued: Bool
    public var holdMilliseconds: Int?
    public var fromCountdown: Bool
    public var tier: HubRiskTier?

    public init(
        action: HubDecisionAction,
        note: String?,
        requestIDs: [String],
        atMilliseconds: Int,
        deniesAllQueued: Bool,
        holdMilliseconds: Int?,
        fromCountdown: Bool,
        tier: HubRiskTier?
    ) {
        self.action = action
        self.note = note
        self.requestIDs = requestIDs
        self.atMilliseconds = atMilliseconds
        self.deniesAllQueued = deniesAllQueued
        self.holdMilliseconds = holdMilliseconds
        self.fromCountdown = fromCountdown
        self.tier = tier
    }
}

public struct HubRevision3State: Equatable, Sendable {
    public var showing: HubRevision3Request?
    public var waiting: [HubRevision3Request]
    public var remainingMilliseconds: Int
    public var pauses: Set<HubCountdownPause>
    public var holdAction: HubDecisionAction?
    public var holdBeganAt: Int?
    public var note: String
    public var pending: HubRevision3Pending?
    public var executed: [HubRevision3Execution]
    public var clock: Int

    public init(
        showing: HubRevision3Request? = nil,
        waiting: [HubRevision3Request] = [],
        remainingMilliseconds: Int = 0,
        pauses: Set<HubCountdownPause> = [],
        holdAction: HubDecisionAction? = nil,
        holdBeganAt: Int? = nil,
        note: String = "",
        pending: HubRevision3Pending? = nil,
        executed: [HubRevision3Execution] = [],
        clock: Int = 0
    ) {
        self.showing = showing
        self.waiting = waiting
        self.remainingMilliseconds = remainingMilliseconds
        self.pauses = pauses
        self.holdAction = holdAction
        self.holdBeganAt = holdBeganAt
        self.note = note
        self.pending = pending
        self.executed = executed
        self.clock = clock
    }

    public var phase: HubRevision3Phase {
        if pending != nil { return .pendingUndo }
        if holdBeganAt != nil { return .holding }
        if showing != nil { return .showing }
        return .idle
    }

    /// True while the person can still choose. False during the undo window and while nothing is showing.
    public var decisionShowing: Bool { showing != nil && pending == nil }

    public var undoShowing: Bool { pending != nil }

    public var waitingCount: Int { waiting.count }

    public var visibleCount: Int { (showing == nil ? 0 : 1) + waiting.count }
}

public enum HubRevision3Phase: String, Equatable, Sendable {
    case idle
    case showing
    case holding
    case pendingUndo
}

public enum HubRevision3Event: Equatable, Sendable {
    case request(HubRevision3Request)
    case advance(to: Int)
    case key(HubDecisionKey, command: Bool)
    case pause(HubCountdownPause, active: Bool)
    case holdBegan(HubDecisionAction, at: Int)
    case holdReleased(at: Int)
    case replaceNote(String)
}

public struct HubRevision3Outcome: Equatable, Sendable {
    public var state: HubRevision3State
    public var announcement: String?

    public init(state: HubRevision3State, announcement: String? = nil) {
        self.state = state
        self.announcement = announcement
    }

    static func unchanged(_ state: HubRevision3State) -> HubRevision3Outcome {
        HubRevision3Outcome(state: state)
    }
}
