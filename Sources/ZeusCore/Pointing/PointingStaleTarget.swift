import Foundation

/// Tracks whether the thing a mark points at is still where it was. Pure: the app feeds it AXObserver
/// notifications and per-beat position reads; it says what to do.
///
/// A mark whose target moved more than `driftTolerance` points, resized, was destroyed or changed
/// value is stale: hide it, try once to re-resolve, and if that fails, ask rather than guess.
public struct PointingStaleTarget: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case fresh
        case stale(Reason)
        case resolving
        case gone
    }

    public enum Reason: String, Equatable, Sendable { case moved, resized, valueChanged, destroyed }

    public enum Event: Equatable, Sendable {
        case moved, resized, valueChanged, destroyed
        /// A per-beat read of the target frame (AX points).
        case observed(x: Double, y: Double, width: Double, height: Double)
        case resolved(x: Double, y: Double, width: Double, height: Double)
        case resolveFailed
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Hide the mark now, then look the target up again and send `resolved` or `resolveFailed`.
        case hideAndReResolve
        /// Hide the mark and tell the user; the string is user-facing.
        case ask(String)
        case showMark
    }

    public static let driftTolerance = 2.0

    public private(set) var phase: Phase = .fresh
    public private(set) var frame: (x: Double, y: Double, width: Double, height: Double)
    private var resolveAttempted = false

    public init(x: Double, y: Double, width: Double, height: Double) { frame = (x, y, width, height) }

    public var isFresh: Bool { phase == .fresh }

    public static func == (a: PointingStaleTarget, b: PointingStaleTarget) -> Bool {
        a.phase == b.phase && a.frame == b.frame
    }

    public mutating func send(_ event: Event) -> Action {
        switch (phase, event) {
        case (.gone, _): return .none
        case (_, .destroyed):
            phase = .gone
            return .ask("That control is gone. Hold the keys and point at it again.")
        case (.fresh, .moved): return markStale(.moved)
        case (.fresh, .resized): return markStale(.resized)
        case (.fresh, .valueChanged): return markStale(.valueChanged)
        case (.fresh, .observed(let x, let y, let w, let h)):
            guard [x, y, w, h].allSatisfy(\.isFinite) else { return markStale(.moved) }
            let drift = max(abs(x - frame.x), abs(y - frame.y), abs(w - frame.width), abs(h - frame.height))
            guard drift > Self.driftTolerance else { return .none }
            let resized = max(abs(w - frame.width), abs(h - frame.height)) > Self.driftTolerance
            return markStale(resized ? .resized : .moved)
        case (.stale, .resolved(let x, let y, let w, let h)), (.resolving, .resolved(let x, let y, let w, let h)):
            frame = (x, y, w, h); phase = .fresh; resolveAttempted = false
            return .showMark
        case (.resolving, .resolveFailed):
            phase = .gone
            return .ask("The screen changed and I lost it. Point at it again.")
        case (.stale, .resolveFailed):
            phase = .gone
            return .ask("The screen changed and I lost it. Point at it again.")
        default:
            return .none
        }
    }

    private mutating func markStale(_ reason: Reason) -> Action {
        phase = .stale(reason)
        if resolveAttempted {
            phase = .gone
            return .ask("That moved again. Point at it once more.")
        }
        resolveAttempted = true
        phase = .resolving
        return .hideAndReResolve
    }
}

extension PointingStaleTarget.Event {
    /// The Accessibility notification names the app observes. Any other name maps to nil.
    public static let observedNotifications = ["AXMoved", "AXResized", "AXUIElementDestroyed", "AXValueChanged"]

    public init?(axNotification name: String) {
        switch name {
        case "AXMoved", "AXWindowMoved": self = .moved
        case "AXResized", "AXWindowResized": self = .resized
        case "AXUIElementDestroyed": self = .destroyed
        case "AXValueChanged": self = .valueChanged
        default: return nil
        }
    }
}
