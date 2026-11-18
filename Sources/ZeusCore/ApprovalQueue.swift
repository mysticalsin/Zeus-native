import Foundation

public struct ApprovalTicket: Equatable, Sendable, Identifiable {
    public var id: String
    public var arrived: Date
    /// The hook helper gives up at this time (115 seconds). A card past it is not shown.
    public var helperDeadline: Date
    public var risk: HookEvent.Risk

    public init(id: String, arrived: Date, helperDeadline: Date, risk: HookEvent.Risk) {
        self.id = id
        self.arrived = arrived
        self.helperDeadline = helperDeadline
        self.risk = risk
    }
}

public enum ApprovalTurn: Equatable, Sendable {
    case show(position: String)
    case waiting(position: String)
    case expired
}

/// FIFO of approval requests. The front card is the only one shown. There is no allow-all.
public struct ApprovalQueueState: Equatable, Sendable {
    public static let allowAllExists = false
    public static let helperDeadline: TimeInterval = 115

    public private(set) var items: [ApprovalTicket] = []

    public init() {}

    public var count: Int { items.count }
    public var front: ApprovalTicket? { items.first }
    /// "1 of N" for the card on screen.
    public var position: String { count == 0 ? "" : "1 of \(count)" }

    public mutating func enqueue(_ ticket: ApprovalTicket, now: Date? = nil) -> ApprovalTurn {
        let now = now ?? ticket.arrived
        guard now < ticket.helperDeadline else { return .expired }
        items.append(ticket)
        items.sort { $0.arrived < $1.arrived }
        guard let index = items.firstIndex(where: { $0.id == ticket.id }) else { return .expired }
        let place = "\(index + 1) of \(items.count)"
        return index == 0 ? .show(position: place) : .waiting(position: place)
    }

    @discardableResult
    public mutating func clearFront() -> ApprovalTicket? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    public mutating func denyAll() -> [ApprovalTicket] {
        let denied = items
        items = []
        return denied
    }
}

public actor ApprovalGate {
    public static let shared = ApprovalGate()
    private var state = ApprovalQueueState()
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    public init() {}

    public var front: ApprovalTicket? { state.front }

    public func position(of id: String) -> String? {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return nil }
        return "\(index + 1) of \(state.count)"
    }

    public func enqueue(_ ticket: ApprovalTicket) -> ApprovalTurn {
        state.enqueue(ticket)
    }

    public func waitUntilFront(_ id: String) async {
        if state.front?.id == id { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[id] = continuation
        }
    }

    @discardableResult
    public func clearFront() -> ApprovalTicket? {
        let removed = state.clearFront()
        if let next = state.front, let waiter = waiters.removeValue(forKey: next.id) {
            waiter.resume()
        }
        return removed
    }
}

extension HookEvent.Risk: Comparable {
    public static func < (lhs: HookEvent.Risk, rhs: HookEvent.Risk) -> Bool {
        func rank(_ risk: HookEvent.Risk) -> Int {
            switch risk {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }
        return rank(lhs) < rank(rhs)
    }
}

public struct ApprovalRiskResult: Equatable, Sendable {
    public var risk: HookEvent.Risk
    public var reasons: [String]

    public init(risk: HookEvent.Risk, reasons: [String]) {
        self.risk = risk
        self.reasons = reasons
    }
}

public enum ApprovalRisk {
    /// The higher of the substring guess and the shell parse. Risk only goes up.
    public static func effective(tool: String?, input: JSONValue?, command: String) -> ApprovalRiskResult {
        let substring = CommandRisk.assess(tool: tool, input: input)
        let shell = ShellRiskClassifier.assess(command)
        var reasons = shell.reasons
        if substring == .high { reasons.append("matched a high-risk pattern") }
        else if substring == .medium { reasons.append("matched a medium-risk pattern") }
        let risk = max(substring, shell.cardRisk)
        if reasons.isEmpty, risk != .low { reasons.append(risk.rawValue) }
        return ApprovalRiskResult(risk: risk, reasons: reasons)
    }
}

public enum ApprovalMethod: Equatable, Sendable {
    case shortcut, spokenYes, trustChat, tap, hold, secondConfirm
}

public enum ApprovalGesture: Equatable, Sendable {
    case tap
    case hold(seconds: Double)
    case secondConfirm
}

public struct AwayNotice: Equatable, Sendable {
    public var informational: Bool
    public var offersAllow: Bool
}

public enum ApprovalPolicy {
    public static let holdDuration = 0.8

    public static func canApprove(risk: HookEvent.Risk, by method: ApprovalMethod) -> Bool {
        switch method {
        case .shortcut, .spokenYes, .trustChat, .tap:
            return risk != .high
        case .hold, .secondConfirm:
            return true
        }
    }

    public static func allowGesture(risk: HookEvent.Risk, reduceMotion: Bool, voiceOver: Bool) -> ApprovalGesture {
        guard risk == .high else { return .tap }
        if reduceMotion || voiceOver { return .secondConfirm }
        return .hold(seconds: holdDuration)
    }

    /// A timeout never allows. High is denied. Anything else keeps the requested verdict, except allow becomes ask.
    public static func timeoutVerdict(risk: HookEvent.Risk, requested: HookDecision.Verdict) -> HookDecision.Verdict {
        if risk == .high { return .deny }
        return requested == .allow ? .ask : requested
    }

    public static func playChime(lockedOrIdle: Bool) -> Bool { !lockedOrIdle }

    public static func awayNotice(lockedOrIdle: Bool, risk: HookEvent.Risk) -> AwayNotice? {
        guard lockedOrIdle else { return nil }
        _ = risk
        return AwayNotice(informational: true, offersAllow: false)
    }
}

public struct ApprovalAudit: Equatable, Sendable {
    public private(set) var entries: [String] = []

    public init() {}

    public mutating func recordTrustedApproval(session: String, command: String) {
        entries.append("trusted approval \(session): \(command)")
    }
}

public actor ApprovalAuditLog {
    public static let shared = ApprovalAuditLog()
    public private(set) var entries: [String] = []

    public func recordTrustedApproval(session: String, command: String) {
        entries.append("trusted approval \(session): \(command)")
    }
}
