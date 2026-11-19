import Foundation

/// One agent's timeline, and the short line used when several agents run at once.
public enum AgentSupervision {
    public struct Step: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable { case step, tool, test }
        public var title: String
        public var kind: Kind
        public var elapsedMs: Int
        public var added: Int
        public var removed: Int
        public var outcome: String?

        public init(title: String, kind: Kind, elapsedMs: Int, added: Int = 0, removed: Int = 0, outcome: String? = nil) {
            self.title = title
            self.kind = kind
            self.elapsedMs = elapsedMs
            self.added = added
            self.removed = removed
            self.outcome = outcome
        }

        /// "+12 −3" when files changed. Empty when both counts are zero.
        public var fileCount: String {
            guard added != 0 || removed != 0 else { return "" }
            return "+\(added) −\(removed)"
        }
    }

    public struct Run: Equatable, Sendable {
        public var steps: [Step]
        public var tokens: Int?
        public var costCents: Int?
        public var allow: String
        public var deny: String
        public var allowHolds: Bool

        public init(steps: [Step], tokens: Int? = nil, costCents: Int? = nil, allow: String, deny: String, allowHolds: Bool) {
            self.steps = steps
            self.tokens = tokens
            self.costCents = costCents
            self.allow = allow
            self.deny = deny
            self.allowHolds = allowHolds
        }
    }

    /// Token and cost lines exist only when a local number was supplied.
    public static func showsUsage(tokens: Int?, costCents: Int?) -> Bool {
        tokens != nil || costCents != nil
    }

    public static func usage(tokens: Int?, costCents: Int?) -> String? {
        switch (tokens, costCents) {
        case let (tokens?, cents?): return "\(tokens) tokens, \(cents)¢"
        case let (tokens?, nil): return "\(tokens) tokens"
        case let (nil, cents?): return "\(cents)¢"
        case (nil, nil): return nil
        }
    }

    /// Allow and Deny come from the approval card. A row that is not waiting has no buttons.
    public static func run(steps: [Step], state: AgentRunState, risk: HookEvent.Risk = .low,
                           tokens: Int? = nil, costCents: Int? = nil) -> Run {
        let waiting = state == .needsYou || state == .stalled
        let buttons = ApprovalCard.buttons(risk: risk, detailsHidden: false, detailHasOwnActions: false)
        return Run(steps: steps, tokens: tokens, costCents: costCents,
                   allow: waiting ? buttons.allow : "",
                   deny: waiting ? buttons.deny : "",
                   allowHolds: waiting && buttons.allowHolds)
    }

    /// One line for several agents. A single agent uses its own status word.
    public static func overview(_ states: [AgentRunState]) -> String {
        guard !states.isEmpty else { return "0 agents" }
        guard states.count > 1 else { return AgentList.word(states[0]) }
        let working = states.filter { $0 == .working }.count
        let waiting = states.filter { $0 == .needsYou || $0 == .stalled }.count
        let failed = states.filter { $0 == .failed }.count
        var parts = ["\(states.count) agents"]
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failed > 0 { parts.append("\(failed) error") }
        return parts.joined(separator: " · ")
    }
}
