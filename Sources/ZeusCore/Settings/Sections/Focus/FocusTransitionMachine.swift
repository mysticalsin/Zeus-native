import Foundation

/// The overlay that appears when a Focus turns on, is replaced, or turns off. The first known reading is a baseline and does not cue.
public struct FocusTransitionMachine: Equatable, Sendable {
    public enum Edge: Equatable, Sendable {
        case turnedOn
        case turnedOff
        case replaced
    }

    public enum State: Equatable, Sendable {
        case off
        case idle
        case loading
        case showing(Edge, String, Double)
        case unavailable
    }

    public enum Event: Equatable, Sendable {
        case setEnabled(Bool)
        case activity(FocusActivity)
        case permissionDenied
        case permissionAllowed
        case tick(Double)
        case dismiss
        case reduceMotion(Bool)
    }

    public enum Effect: Equatable, Sendable {
        case show(String, Double)
        case hide
    }

    public static let dwell = 2.5

    public static func animationDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : MotionTokens.crossfadeDuration
    }

    public private(set) var state: State = .off
    public private(set) var enabled = false
    public private(set) var baseline: FocusActivity?
    public private(set) var reduceMotion = false
    public private(set) var now: Double = 0

    public init() {}

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .setEnabled(let on):
            enabled = on
            baseline = nil
            guard on else {
                let hide = isShowing
                state = .off
                return hide ? [.hide] : []
            }
            state = .loading
            return []
        case .activity(let activity):
            guard enabled, state != .unavailable else { return [] }
            switch activity {
            case .unknown:
                baseline = nil
                state = .loading
                return isShowing ? [.hide] : []
            case .off, .on:
                if baseline == nil {
                    baseline = activity
                    state = .idle
                    return []
                }
                guard let change = Self.change(from: baseline!, to: activity) else {
                    baseline = activity
                    return []
                }
                baseline = activity
                state = .showing(change.edge, change.label, now)
                return [.show(change.label, Self.animationDuration(reduceMotion: reduceMotion))]
            }
        case .permissionDenied:
            guard enabled else { return [] }
            baseline = nil
            let hide = isShowing
            state = .unavailable
            return hide ? [.hide] : []
        case .permissionAllowed:
            guard enabled else { return [] }
            baseline = nil
            let hide = isShowing
            state = .loading
            return hide ? [.hide] : []
        case .tick(let time):
            now = time
            guard case .showing(_, _, let since) = state, time - since >= Self.dwell else { return [] }
            state = .idle
            return [.hide]
        case .dismiss:
            guard isShowing else { return [] }
            state = .idle
            return [.hide]
        case .reduceMotion(let on):
            reduceMotion = on
            return []
        }
    }

    private var isShowing: Bool {
        if case .showing = state { return true }
        return false
    }

    private struct Change {
        var edge: Edge
        var label: String
    }

    private static func change(from: FocusActivity, to: FocusActivity) -> Change? {
        switch (from, to) {
        case (.off, .on(let name)):
            return Change(edge: .turnedOn, label: name ?? "Focus on")
        case (.on, .off):
            return Change(edge: .turnedOff, label: "Focus off")
        case (.on(let previous), .on(let name)) where previous != name:
            return Change(edge: .replaced, label: name ?? "Focus on")
        default:
            return nil
        }
    }
}
