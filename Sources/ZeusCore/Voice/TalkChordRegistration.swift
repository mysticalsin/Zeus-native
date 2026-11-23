import Foundation

/// Whether Control-Option-Space should be registered. The Carbon call stays in the app.
/// A paused monitor, or one that cannot hear keys, wants no chord. A refusal is asked again.
/// A chord that is already held is left alone.
public struct TalkChordRegistration: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case clear
        case holding(Shortcut)
        case refused(Shortcut)
    }

    public enum Effect: Equatable, Sendable {
        case register(Shortcut)
        case unregister
    }

    public private(set) var state: State

    private var desired: Shortcut?
    private var paused: Bool
    private var listening: Bool
    private var attempted: Shortcut?

    public init() {
        state = .clear
        desired = nil
        paused = false
        listening = true
        attempted = nil
    }

    public mutating func sync(_ chord: Shortcut?, listening: Bool) -> [Effect] {
        desired = chord
        self.listening = listening
        return apply()
    }

    public mutating func pause() -> [Effect] {
        guard !paused else { return [] }
        paused = true
        return apply()
    }

    public mutating func resume() -> [Effect] {
        guard paused else { return [] }
        paused = false
        return apply()
    }

    /// The app reports whether the registrar accepted the chord from the last `.register`.
    public mutating func noteRegistered(_ registered: Bool) {
        guard let attempted, attempted.keyCode != nil else { return }
        state = registered ? .holding(attempted) : .refused(attempted)
    }

    private var isHolding: Bool {
        if case .holding = state { return true }
        return false
    }

    private mutating func apply() -> [Effect] {
        let want = paused || !listening ? nil : desired
        guard want != attempted || (want != nil && !isHolding) else { return [] }
        var effects: [Effect] = []
        if isHolding { effects.append(.unregister) }
        attempted = want
        guard let want, want.keyCode != nil else {
            state = .clear
            return effects
        }
        effects.append(.register(want))
        state = .refused(want)
        return effects
    }
}
