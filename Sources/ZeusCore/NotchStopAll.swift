import Foundation

/// Where a notch session came from. Zeus either launched it or a hook reported it.
public enum SupervisedOrigin: String, Equatable, Sendable {
    case started
    case hooked
}

/// One run the notch is supervising. An approval card is not a run.
public struct SupervisedRun: Equatable, Sendable, Identifiable {
    public var id: String
    public var origin: SupervisedOrigin
    public var status: AgentRunState

    public init(id: String, origin: SupervisedOrigin, status: AgentRunState) {
        self.id = id
        self.origin = origin
        self.status = status
    }
}

/// What one stop-all does. Pending approvals are outside this plan.
public struct NotchStopPlan: Equatable, Sendable {
    /// Active supervised runs, in the order they were given.
    public var halted: [String]
    /// Zeus-started runs that registered a stop. The caller invokes that stop.
    public var callHandlers: [String]
    /// Hooked runs with no stop of their own. The caller sends an interrupt when a tty is known.
    public var interrupt: [String]

    public init(halted: [String], callHandlers: [String], interrupt: [String]) {
        self.halted = halted
        self.callHandlers = callHandlers
        self.interrupt = interrupt
    }
}

/// Stop every run Zeus started or hooked. Idle, finished and failed runs stay as they are.
public enum NotchStopAll {
    public static let stoppedTask = "Stopped"

    /// Working, stalled, or waiting. Idle, done and failed are not halted again.
    public static func isActive(_ status: AgentRunState) -> Bool {
        switch status {
        case .working, .stalled, .needsYou: true
        case .idle, .done, .failed: false
        }
    }

    public static func plan(_ runs: [SupervisedRun], handlers: Set<String>) -> NotchStopPlan {
        var halted: [String] = []
        var callHandlers: [String] = []
        var interrupt: [String] = []
        for run in runs where isActive(run.status) {
            halted.append(run.id)
            if handlers.contains(run.id) {
                callHandlers.append(run.id)
            } else if run.origin == .hooked {
                interrupt.append(run.id)
            }
        }
        return NotchStopPlan(halted: halted, callHandlers: callHandlers, interrupt: interrupt)
    }

    /// Voice stop is optional. Off matches nothing, including a bare "stop", so the browser
    /// agent and a walkthrough keep that word. On matches a whole stop-all phrase.
    public static func matchesVoice(_ transcript: String, enabled: Bool) -> Bool {
        guard enabled else { return false }
        let key = Utterance(transcript).words.joined(separator: " ")
        return phrases.contains(key)
    }

    /// A device Zeus may write one interrupt byte to. Anything else is refused.
    public static func interruptDevice(_ tty: String?) -> String? {
        guard let tty, let safe = TerminalTabScript.safe(tty) else { return nil }
        if safe.range(of: #"^/dev/tty[A-Za-z0-9]+$"#, options: .regularExpression) != nil { return safe }
        if safe.range(of: #"^/dev/pts/[0-9]+$"#, options: .regularExpression) != nil { return safe }
        return nil
    }

    private static let phrases: Set<String> = [
        "stop all",
        "stop all agents",
        "stop the agents",
        "stop every agent",
        "stop agents",
        "halt all",
        "halt all agents",
        "halt the agents",
    ]
}
