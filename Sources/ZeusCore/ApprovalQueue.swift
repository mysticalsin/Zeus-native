import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
    case duplicate
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
        if items.contains(where: { $0.id == ticket.id }) { return .duplicate }
        items.append(ticket)
        items.sort { $0.arrived < $1.arrived }
        guard let index = items.firstIndex(where: { $0.id == ticket.id }) else { return .expired }
        let place = "\(index + 1) of \(items.count)"
        return index == 0 ? .show(position: place) : .waiting(position: place)
    }

    /// Puts `id` at the front and leaves the others queued behind it, in their previous order.
    @discardableResult
    public mutating func moveToFront(id: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        guard index > 0 else { return true }
        let ticket = items.remove(at: index)
        items.insert(ticket, at: 0)
        return true
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

    /// Drops every ticket whose helper deadline has been reached. The caller supplies the clock.
    public mutating func dropExpired(now: Date) -> [ApprovalTicket] {
        let expired = items.filter { now >= $0.helperDeadline }
        items.removeAll { now >= $0.helperDeadline }
        return expired
    }
}

public actor ApprovalGate {
    public static let shared = ApprovalGate()
    private var state = ApprovalQueueState()
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<String> = []
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public var front: ApprovalTicket? { state.front }

    public func position(of id: String) -> String? {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return nil }
        return "\(index + 1) of \(state.count)"
    }

    public func enqueue(_ ticket: ApprovalTicket) -> ApprovalTurn {
        sweep()
        if state.items.contains(where: { $0.id == ticket.id }) || waiters[ticket.id] != nil {
            return .duplicate
        }
        return state.enqueue(ticket, now: now())
    }

    public func waitUntilFront(_ id: String) async {
        if state.front?.id == id { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if waiters[id] != nil {
                continuation.resume()
                return
            }
            waiters[id] = continuation
        }
    }

    /// The displayed request becomes the one Allow and Deny resolve.
    public func focus(_ id: String) {
        _ = state.moveToFront(id: id)
    }

    /// Removes the front card only when it is still this request.
    @discardableResult
    public func clearFront(id: String) -> ApprovalTicket? {
        guard state.front?.id == id else { return nil }
        let removed = state.clearFront()
        wakeNext()
        return removed
    }

    public func denyAll() {
        let denied = state.denyAll()
        for ticket in denied {
            cancelled.insert(ticket.id)
            waiters.removeValue(forKey: ticket.id)?.resume()
        }
    }

    public func wasCancelled(_ id: String) -> Bool {
        cancelled.remove(id) != nil
    }

    /// False once the helper deadline has passed or this request is not the front card.
    public func permits(_ id: String) -> Bool {
        sweep()
        guard let front = state.front, front.id == id else { return false }
        return now() < front.helperDeadline
    }

    private func sweep() {
        for ticket in state.dropExpired(now: now()) {
            cancelled.insert(ticket.id)
            waiters.removeValue(forKey: ticket.id)?.resume()
        }
    }

    private func wakeNext() {
        if let next = state.front, let waiter = waiters.removeValue(forKey: next.id) {
            waiter.resume()
        }
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
    case shortcut, spokenYes, trustChat, tap, hold, onScreenConfirm
}

public enum ApprovalGesture: Equatable, Sendable {
    case tap
    case hold(seconds: Double)
    /// A second press of the on-screen button, after a wait and before it expires. Shortcut and voice never count.
    case onScreenConfirm(readyAfter: Double, expiresAfter: Double)
}

public struct AwayNotice: Equatable, Sendable {
    public var informational: Bool
    public var offersAllow: Bool
}

public enum ApprovalPolicy {
    public static let holdDuration = 0.8
    /// The on-screen confirm cannot be the same instant as the first press.
    public static let confirmReadyAfter = 0.4
    /// The confirm step goes away if the button is not pressed again in time.
    public static let confirmExpiresAfter = 8.0

    public static func canApprove(risk: HookEvent.Risk, by method: ApprovalMethod) -> Bool {
        switch method {
        case .shortcut, .spokenYes, .trustChat, .tap:
            return risk != .high
        case .hold, .onScreenConfirm:
            return true
        }
    }

    public static func allowGesture(risk: HookEvent.Risk, reduceMotion: Bool, voiceOver: Bool) -> ApprovalGesture {
        guard risk == .high else { return .tap }
        if reduceMotion || voiceOver {
            return .onScreenConfirm(readyAfter: confirmReadyAfter, expiresAfter: confirmExpiresAfter)
        }
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

public struct ApprovalAllowGate: Equatable, Sendable {
    public enum Channel: Equatable, Sendable {
        /// The on-screen Allow button, including its VoiceOver action.
        case onScreen
        case shortcut
        case voice
    }

    public var risk: HookEvent.Risk
    public var reduceMotion: Bool
    public var voiceOver: Bool
    /// The request this hold belongs to. A release for another id does not allow.
    public var itemID: String
    /// Monotonic seconds from `ApprovalMonotonic.now`, which keeps moving while the Mac sleeps.
    public private(set) var holdingSince: TimeInterval?
    public private(set) var holdingItem: String?
    /// When the on-screen confirm step was armed, in the same monotonic clock.
    public private(set) var confirmArmedAt: TimeInterval?

    public init(risk: HookEvent.Risk, reduceMotion: Bool = false, voiceOver: Bool = false, itemID: String = "") {
        self.risk = risk
        self.reduceMotion = reduceMotion
        self.voiceOver = voiceOver
        self.itemID = itemID
    }

    public var gesture: ApprovalGesture {
        ApprovalPolicy.allowGesture(risk: risk, reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    public var confirmVisible: Bool { confirmArmedAt != nil }

    /// Shortcut and voice never allow a high-risk request. The on-screen confirm allows only inside its window.
    public mutating func activate(now: TimeInterval, channel: Channel = .onScreen) -> HookDecision.Verdict? {
        if risk == .high, channel != .onScreen { return nil }
        switch gesture {
        case .tap:
            return .allow
        case .hold:
            return nil
        case .onScreenConfirm(let ready, let expires):
            guard channel == .onScreen else { return nil }
            guard let armed = confirmArmedAt else {
                confirmArmedAt = now
                return nil
            }
            if now > armed + expires {
                confirmArmedAt = nil
                return nil
            }
            if now < armed + ready { return nil }
            confirmArmedAt = nil
            return .allow
        }
    }

    /// A different request, or a higher risk, cannot inherit this hold, this confirm, or a low-risk tap.
    public mutating func retarget(item id: String, risk: HookEvent.Risk? = nil) {
        let nextRisk = risk ?? self.risk
        let changed = id != itemID || nextRisk != self.risk
        itemID = id
        self.risk = nextRisk
        if changed {
            cancelHold()
            confirmArmedAt = nil
        }
    }

    public mutating func beginHold(now: TimeInterval) {
        guard case .hold = gesture, holdingSince == nil else { return }
        holdingSince = now
        holdingItem = itemID
    }

    /// Ends a press. A release outside the button, or for another item, clears the hold and does not allow.
    public mutating func releaseHold(now: TimeInterval, inside: Bool) -> HookDecision.Verdict? {
        defer { cancelHold() }
        guard inside, holdingItem == itemID, let start = holdingSince, case .hold(let seconds) = gesture else { return nil }
        return now >= start + seconds ? .allow : nil
    }

    public mutating func cancelHold() {
        holdingSince = nil
        holdingItem = nil
    }

    public func holdFraction(now: TimeInterval) -> Double {
        guard case .hold(let seconds) = gesture, let start = holdingSince, seconds > 0 else { return 0 }
        return min(max((now - start) / seconds, 0), 1)
    }
}

/// Whether a press is still down. A system cancel has no release, so the hold must be cleared then.
public struct ApprovalHoldTracking: Equatable {
    public var down = false
    public var released = false

    public mutating func press() { down = true; released = false }

    public mutating func release() { released = true; down = false }

    /// True when the gesture was cancelled before it ended. The hold must be cleared.
    public mutating func systemCancel() -> Bool {
        let clear = down && !released
        down = false
        return clear
    }
}

/// A release counts only when the card under the pointer is the card the press started on.
public enum ApprovalPressOrigin: Equatable, Sendable {
    public static func releaseCounts(pressed: String, displayed: String) -> Bool { true }
}

/// Approve Plan and Send Answers. An inside release is still treated as the end of a hold.
public enum ApprovalDetailPress: Equatable, Sendable {
    public static func planRelease(inside: Bool, gesture: ApprovalGesture) -> ApprovalPress {
        ApprovalPress.outcome(inside: inside, gesture: gesture)
    }
}

/// What a pointer release on the Allow button does. A release outside the control never counts.
public enum ApprovalPress: Equatable, Sendable {
    case cancel
    case endHold
    case activate

    public static func outcome(inside: Bool, gesture: ApprovalGesture) -> ApprovalPress {
        guard inside else { return .cancel }
        if case .hold = gesture { return .endHold }
        return .activate
    }
}

/// The Allow button's hit test, in the button's own coordinates.
public enum ApprovalButtonHit {
    public static func contains(width: Double, height: Double, x: Double, y: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 0 && height >= 0
            && x.isFinite && y.isFinite && x >= 0 && y >= 0 && x <= width && y <= height
    }
}

/// A clock that keeps advancing while the machine sleeps. `ProcessInfo.systemUptime` does not.
public enum ApprovalMonotonic {
    public static func now() -> TimeInterval {
        var value = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &value) == 0 else { return 0 }
        return TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000
    }
}

public struct ApprovalAudit: Equatable, Sendable {
    public static let capacity = 200
    public enum Kind: String, Equatable, Sendable {
        case card, shortcut, voice, timeout, trusted
    }

    public private(set) var entries: [String] = []

    public init() {}

    public static func plain(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return scalar.value >= 32 && scalar.value != 127 && scalar.value != 0x2028 && scalar.value != 0x2029
                && category != .control && category != .lineSeparator && category != .paragraphSeparator
        }.map(Character.init))
    }

    public mutating func record(kind: Kind, session: String, command: String, verdict: String) {
        entries.append("\(kind.rawValue) \(Self.plain(session)): \(Self.plain(command)) \(Self.plain(verdict))")
        trim()
    }

    public mutating func recordTrustedApproval(session: String, command: String) {
        entries.append("trusted approval \(Self.plain(session)): \(Self.plain(command))")
        trim()
    }

    private mutating func trim() {
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }
}

public actor ApprovalAuditLog {
    public static let shared = ApprovalAuditLog()
    private var audit = ApprovalAudit()
    public var entries: [String] { audit.entries }

    public func record(kind: ApprovalAudit.Kind, session: String, command: String, verdict: String) {
        audit.record(kind: kind, session: session, command: command, verdict: verdict)
    }

    public func recordTrustedApproval(session: String, command: String) {
        audit.recordTrustedApproval(session: session, command: command)
    }
}
