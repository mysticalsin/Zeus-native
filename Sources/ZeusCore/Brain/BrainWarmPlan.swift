import Foundation

/// When to keep the brains warm, so a cold first token (TLS and HTTP/2 setup, or a model reloading) never
/// lands on Tony's question. Pure: the Zeus target owns the timer and the pings.
///
/// QA23 saw a 1056 ms first token against 551 to 813 ms for the rest: the one turn after a quiet stretch
/// paid for a fresh connection, because the launch ping ran once and idle connections close within minutes.
public enum BrainWarmPlan {
    public enum Target: Sendable, Hashable { case localModel, cloudConnection }

    /// Zeus counts as "in use" this long after Tony last pressed the key, spoke or asked something.
    public static let activeWindow: TimeInterval = 30 * 60
    /// An idle HTTPS connection to the cloud API is dropped after a few minutes.
    public static let cloudInterval: TimeInterval = 4 * 60
    /// Ollama keeps a model for `keep_alive` (30 min); the ping lands well before that.
    public static let localInterval: TimeInterval = 20 * 60
    /// How often the scheduler looks at all (a loose timer with tolerance, never a tight loop).
    public static let checkEvery: TimeInterval = 120

    /// What starts a warm-up. Launch and wake from sleep are deliberately not on the list: an app that
    /// has not been spoken to makes no network call and loads no model.
    public enum Trigger: Sendable, Hashable { case launch, wake, talkKeyDown, voiceActivity, idleCheck }

    /// Whether this trigger may start a warm-up at all.
    public static func mayWarm(on trigger: Trigger) -> Bool {
        switch trigger {
        case .launch, .wake: false
        case .talkKeyDown, .voiceActivity, .idleCheck: true
        }
    }

    /// What to warm now. Nothing happens until the person has used voice (`lastActivity`), and not
    /// after the active window ends, so an idle Mac makes no calls.
    public static func due(now: Date, lastActivity: Date?, lastCloud: Date?, lastLocal: Date?) -> Set<Target> {
        guard let lastActivity, now.timeIntervalSince(lastActivity) <= activeWindow else { return [] }
        var targets: Set<Target> = []
        if lastCloud.map({ now.timeIntervalSince($0) >= cloudInterval }) ?? true { targets.insert(.cloudConnection) }
        if lastLocal.map({ now.timeIntervalSince($0) >= localInterval }) ?? true { targets.insert(.localModel) }
        return targets
    }

    /// True once the active window has passed: the scheduler stops its timer.
    public static func isIdle(now: Date, lastActivity: Date?) -> Bool {
        guard let lastActivity else { return true }
        return now.timeIntervalSince(lastActivity) > activeWindow
    }
}

/// Remembers how fast each engine's first token has been, so the race pair is the two fastest.
/// A failed or missing engine counts as slow, so a local server that is not running stops taking a race slot.
public final class BrainLatencyBook: @unchecked Sendable {
    public static let shared = BrainLatencyBook()
    /// What a failure counts as, in ms.
    public static let failurePenaltyMs = 10_000.0

    private let lock = NSLock()
    private var average: [String: Double] = [:]

    public init() {}

    public func record(_ engine: String, firstTokenMs: Double) {
        lock.withLock {
            average[engine] = average[engine].map { $0 * 0.6 + firstTokenMs * 0.4 } ?? firstTokenMs
        }
    }

    public func recordFailure(_ engine: String) { record(engine, firstTokenMs: Self.failurePenaltyMs) }

    public func average(for engine: String) -> Double? { lock.withLock { average[engine] } }

    /// What an engine with no measurement yet is assumed to cost, in ms.
    public static let unmeasuredMs = 800.0

    /// Reorders the engines that answer over HTTP (the race pair is drawn from the front), fastest
    /// first; ties and unmeasured engines keep their order, and CLI engines stay behind them. "ollama"
    /// counts as HTTP only at the very front: later it is the CLI of the same name.
    public func ordered<T>(_ items: [T], id: (T) -> String) -> [T] {
        let http: Set<String> = ["ollama", "anthropic-api", "openai"]
        var count = 0
        for (index, item) in items.enumerated() {
            let name = id(item)
            guard http.contains(name), name != "ollama" || index == 0 else { break }
            count += 1
        }
        let measured = lock.withLock { average }
        let head = items.prefix(count).enumerated().sorted { lhs, rhs in
            let a = measured[id(lhs.element)] ?? Self.unmeasuredMs
            let b = measured[id(rhs.element)] ?? Self.unmeasuredMs
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
        return head + Array(items.dropFirst(count))
    }
}
