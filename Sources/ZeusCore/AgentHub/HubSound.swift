import Foundation

/// Which hub cues are heard. The master switch starts off, so nothing plays until an opt-in.
/// Cue choice is the existing chime policy. This type does not play a sound.
public struct HubSound: Sendable {
    /// A turn shorter than this finishes silently.
    public static let minWorkSeconds = AgentChimePolicy.minWorkSeconds
    /// At most one cue inside this window, across every session.
    public static let coalesceSeconds = AgentChimePolicy.coalesceSeconds

    public private(set) var status: HubSoundStatus
    private var policy = AgentChimePolicy()

    public init() {
        status = .silent
    }

    /// The sound table. A pair the table does not name leaves the status as it is.
    /// Opting out from `playing` returns to silence, so a cue that is already going stops.
    public static func next(_ status: HubSoundStatus, _ event: HubSoundEvent) -> HubSoundStatus {
        switch (status, event) {
        case (.silent, .optIn):
            return .armed
        case (.armed, .optOut), (.playing, .optOut):
            return .silent
        case (.armed, .cueAllowed):
            return .playing
        case (.armed, .cueSuppressed):
            return .armed
        case (.playing, .soundEnded):
            return .armed
        default:
            return status
        }
    }

    @discardableResult
    public mutating func apply(_ event: HubSoundEvent) -> HubSoundStatus {
        status = Self.next(status, event)
        return status
    }

    /// One session tick. While the switch is off the policy is not asked, and the cue is silence.
    public mutating func session(
        _ id: String, status run: AgentRunState, at now: Date, startEnabled: Bool
    ) -> HubSoundDecision {
        guard status != .silent else {
            return HubSoundDecision(status: status, cues: [])
        }
        return decided(policy.session(id, status: run, at: now, startEnabled: startEnabled))
    }

    /// One approval tick. While the switch is off, silence.
    public mutating func approval(visible: Bool, at now: Date) -> HubSoundDecision {
        guard status != .silent else {
            return HubSoundDecision(status: status, cues: [])
        }
        return decided(policy.approval(visible: visible, at: now))
    }

    /// One finish. The extra finish sound is not returned beside the policy cue, and it does not fill silence.
    public mutating func finish(
        _ id: String, at now: Date, startEnabled: Bool, systemFinishSound: Bool
    ) -> HubSoundDecision {
        let decision = session(id, status: .done, at: now, startEnabled: startEnabled)
        let cues = Self.finishCues(decision.cues, systemFinishSound: systemFinishSound)
        return HubSoundDecision(status: decision.status, cues: cues)
    }

    /// Drops stretch state for sessions that are gone.
    public mutating func forget(keeping alive: Set<String>) {
        policy.forget(keeping: alive)
    }

    /// Zero cues, or the one policy cue. `systemFinishSound` never adds a second cue.
    static func finishCues(_ policyCues: [HubSoundCue], systemFinishSound: Bool) -> [HubSoundCue] {
        guard let cue = policyCues.first else { return [] }
        if systemFinishSound { return [cue] }
        return [cue]
    }

    private mutating func decided(_ cue: AgentChimePolicy.Cue?) -> HubSoundDecision {
        guard let cue else {
            status = Self.next(status, .cueSuppressed)
            return HubSoundDecision(status: status, cues: [])
        }
        status = Self.next(status, .cueAllowed)
        return HubSoundDecision(status: status, cues: [HubSoundCue(cue)])
    }
}

/// The status after a cue decision, and the cues to play. A finish carries at most one.
public struct HubSoundDecision: Equatable, Sendable {
    public var status: HubSoundStatus
    public var cues: [HubSoundCue]

    public init(status: HubSoundStatus, cues: [HubSoundCue]) {
        self.status = status
        self.cues = cues
    }
}

extension HubSoundCue {
    init(_ cue: AgentChimePolicy.Cue) {
        switch cue {
        case .start: self = .start
        case .done: self = .done
        case .approval: self = .approval
        case .answer: self = .answer
        }
    }
}
