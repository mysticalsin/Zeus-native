import Foundation

/// How long an incoming alert stays up, and whether it stays at all.
public enum AlertPriority: Int, Comparable, Sendable {
    case low, normal, high, urgent

    public static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Seconds on screen once visible. Urgent alerts stay until the person acts.
    public var autoDismissSeconds: TimeInterval? {
        switch self {
        case .low: 4
        case .normal: 6
        case .high: 10
        case .urgent: nil
        }
    }
}

public struct AlertItem: Equatable, Identifiable, Sendable {
    public var id: String
    public var appID: String
    public var appName: String
    public var title: String
    public var body: String
    public var priority: AlertPriority
    public var postedAt: Date
    /// How many identical alerts were folded into this one.
    public var count: Int

    public init(id: String, appID: String, appName: String, title: String, body: String,
                priority: AlertPriority = .normal, postedAt: Date, count: Int = 1) {
        self.id = id; self.appID = appID; self.appName = appName; self.title = title; self.body = body
        self.priority = priority; self.postedAt = postedAt; self.count = count
    }

    /// Same app, title and body: the same alert for coalescing.
    public var dedupeKey: String { "\(appID)\u{1F}\(title)\u{1F}\(body)" }

    /// What VoiceOver says once, when the alert first appears.
    public var spokenText: String { [appName, title, body].filter { !$0.isEmpty }.joined(separator: ". ") }
}

/// The queue behind the incoming-alert capsule. Pure value type: the view layer owns one and asks it what to
/// show and when to wake next, so an idle stack needs no timer.
public struct AlertStack: Equatable, Sendable {
    /// Identical alerts inside this window become one card with a count.
    public static let coalesceWindow: TimeInterval = 5
    public static let maxVisible = 3
    /// After the pointer leaves, a card keeps at least this long so a hover never ends in an instant dismissal.
    public static let minimumAfterHover: TimeInterval = 1.5

    public enum PostResult: Equatable, Sendable {
        case added(String)
        case coalesced(String)
    }

    /// Newest first. The first `maxVisible` are shown; the rest wait their turn.
    public private(set) var items: [AlertItem] = []
    public private(set) var isHovered = false
    /// True while the capsule cannot be seen (the notch is open, a peek or the panel covers it): timers pause so an
    /// alert is never dismissed unseen.
    public private(set) var isSuspended = false
    private var deadlines: [String: Date] = [:]
    private var frozenRemaining: [String: TimeInterval] = [:]

    public init() {}

    public var visible: [AlertItem] { Array(items.prefix(Self.maxVisible)) }
    /// The "+2" chip.
    public var hiddenCount: Int { max(0, items.count - Self.maxVisible) }
    public var isEmpty: Bool { items.isEmpty }
    /// Every timer is frozen: hovered, or not on screen.
    public var isPaused: Bool { isHovered || isSuspended }

    @discardableResult
    public mutating func post(_ alert: AlertItem, now: Date) -> PostResult {
        if let index = items.firstIndex(where: { $0.dedupeKey == alert.dedupeKey && now.timeIntervalSince($0.postedAt) <= Self.coalesceWindow }) {
            var merged = items.remove(at: index)
            merged.count += 1
            merged.postedAt = now
            merged.priority = max(merged.priority, alert.priority)
            items.insert(merged, at: 0)
            deadlines[merged.id] = nil
            frozenRemaining[merged.id] = nil
            refresh(now: now)
            return .coalesced(merged.id)
        }
        var fresh = alert
        fresh.postedAt = now
        items.insert(fresh, at: 0)
        refresh(now: now)
        return .added(fresh.id)
    }

    public mutating func dismiss(id: String, now: Date) {
        items.removeAll { $0.id == id }
        deadlines[id] = nil
        frozenRemaining[id] = nil
        // With nothing left there is nothing to hover: a stale hover would stop the next alert's clock from ever starting.
        if items.isEmpty { isHovered = false }
        refresh(now: now)
    }

    public mutating func clear() {
        items = []; deadlines = [:]; frozenRemaining = [:]; isHovered = false
    }

    /// Hovering the capsule pauses every timer; leaving resumes with the time that was left.
    public mutating func setHovered(_ hovered: Bool, now: Date) {
        guard hovered != isHovered else { return }
        let wasPaused = isPaused
        isHovered = hovered
        syncPause(wasPaused: wasPaused, now: now)
    }

    /// The capsule is hidden (true) or on screen again (false). Hidden alerts keep their place and their remaining time.
    public mutating func setSuspended(_ suspended: Bool, now: Date) {
        guard suspended != isSuspended else { return }
        let wasPaused = isPaused
        isSuspended = suspended
        syncPause(wasPaused: wasPaused, now: now)
    }

    private mutating func syncPause(wasPaused: Bool, now: Date) {
        guard wasPaused != isPaused else { return }
        if isPaused {
            for (id, deadline) in deadlines { frozenRemaining[id] = max(0, deadline.timeIntervalSince(now)) }
            deadlines = [:]
        } else {
            for (id, left) in frozenRemaining where items.contains(where: { $0.id == id }) {
                deadlines[id] = now.addingTimeInterval(max(left, Self.minimumAfterHover))
            }
            frozenRemaining = [:]
            refresh(now: now)
        }
    }

    /// Removes visible alerts whose time is up and returns their ids (newest first).
    @discardableResult
    public mutating func expire(now: Date) -> [String] {
        guard !isPaused else { return [] }
        let due = visible.filter { item in deadlines[item.id].map { $0 <= now } ?? false }.map(\.id)
        for id in due { dismiss(id: id, now: now) }
        return due
    }

    /// When the owner should wake next. Nil when nothing will expire by itself (empty, hovered, or only urgent
    /// alerts), so the owner cancels its sleep and the surface is fully idle.
    public func nextDeadline() -> Date? {
        guard !isPaused else { return nil }
        return visible.compactMap { deadlines[$0.id] }.min()
    }

    /// Gives every visible alert without a deadline one (a card that just reached the front starts its clock then).
    private mutating func refresh(now: Date) {
        guard !isPaused else { return }
        for item in visible where deadlines[item.id] == nil {
            if let seconds = item.priority.autoDismissSeconds { deadlines[item.id] = now.addingTimeInterval(seconds) }
        }
        let shown = Set(visible.map(\.id))
        deadlines = deadlines.filter { shown.contains($0.key) }
    }
}
