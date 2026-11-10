import Foundation

/// One key, two gestures (right Command by default): hold to dictate, double-tap to talk to
/// ZEUS. A press that meets any other key (⌘C, ⌘Tab) is ignored, so shortcuts keep working:
/// dictation only begins after the key is held alone for `holdDelay`.
/// Pure state, unit tested; HotkeyMonitor feeds it events and runs the one hold timer.
public struct SharedKeyGesture: Sendable {
    public enum Output: Equatable, Sendable { case holdBegan, holdEnded, holdCancelled, doubleTap }

    private enum State: Equatable, Sendable {
        case idle
        case down(at: TimeInterval, second: Bool, holding: Bool, spoiled: Bool)
        case tapped(up: TimeInterval)
    }

    public var holdDelay: TimeInterval = 0.25
    public var tapMax: TimeInterval = 0.25
    public var doubleTapGap: TimeInterval = 0.35
    private var state: State = .idle

    public init() {}

    /// Dictation is running from a hold (Shift joining now means "press Return", not a shortcut).
    public var isHolding: Bool {
        if case .down(_, _, true, _) = state { return true }
        return false
    }

    public mutating func keyDown(at t: TimeInterval) {
        switch state {
        case .tapped(let up) where t - up <= doubleTapGap:
            state = .down(at: t, second: true, holding: false, spoiled: false)
        case .down:
            break
        default:
            state = .down(at: t, second: false, holding: false, spoiled: false)
        }
    }

    /// The hold timer, scheduled `holdDelay` after keyDown.
    public mutating func holdTimerFired(at t: TimeInterval) -> Output? {
        guard case .down(let at, let second, false, false) = state, t - at >= holdDelay - 0.001 else { return nil }
        state = .down(at: at, second: second, holding: true, spoiled: false)
        return .holdBegan
    }

    /// Any non-modifier key, or another modifier, while the key is down.
    public mutating func otherKey() -> Output? {
        guard case .down(let at, let second, let holding, _) = state else {
            if case .tapped = state { state = .idle }
            return nil
        }
        state = .down(at: at, second: second, holding: false, spoiled: true)
        return holding ? .holdCancelled : nil
    }

    public mutating func keyUp(at t: TimeInterval) -> Output? {
        guard case .down(let at, let second, let holding, let spoiled) = state else { return nil }
        if holding { state = .idle; return .holdEnded }
        if spoiled { state = .idle; return nil }
        let quick = t - at <= tapMax
        if quick && second { state = .idle; return .doubleTap }
        state = quick ? .tapped(up: t) : .idle
        return nil
    }
}
