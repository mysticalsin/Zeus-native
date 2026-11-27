import Foundation

/// One action the app is ready to run after the proposal gate. The text is what would be
/// written. It is never the contents of the focused field.
public struct PointingActionRequest: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case insertText
        case writeClipboard
    }

    /// A verb that always asks, even when the caller marked the action quiet.
    public enum Privilege: String, Equatable, Sendable {
        case none
        case send
        case delete
        case purchase
        case publish
    }

    public enum Risk: Int, Equatable, Comparable, Sendable {
        case safe, undoable, risky, destructive
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static let maxTextBytes = 2_000
    public static let maxSummaryBytes = 200
    public static let maxIdentifierBytes = 64

    public var id: String
    public var kind: Kind
    public var summary: String
    public var text: String
    public var risk: Risk
    public var privilege: Privilege
    public var focusedFieldIsSecure: Bool

    public init(
        id: String,
        kind: Kind,
        summary: String,
        text: String,
        risk: Risk,
        privilege: Privilege = .none,
        focusedFieldIsSecure: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.text = text
        self.risk = risk
        self.privilege = privilege
        self.focusedFieldIsSecure = focusedFieldIsSecure
    }
}

/// The card the person sees before a risky action. It carries the summary, not the payload.
public struct PointingActionCard: Equatable, Sendable {
    public var id: String
    public var summary: String
    public var kind: PointingActionRequest.Kind

    public init(id: String, summary: String, kind: PointingActionRequest.Kind) {
        self.id = id
        self.summary = summary
        self.kind = kind
    }
}

/// Shown after the sink runs, or after the person cancels while the card is up.
public struct PointingActionIndicator: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case done
        case cancelled
    }

    public var id: String
    public var state: State
    public var summary: String

    public init(id: String, state: State, summary: String) {
        self.id = id
        self.state = state
        self.summary = summary
    }
}

/// Why nothing ran. The explanation never repeats the payload or a field value.
public struct PointingActionRefusal: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case secureField
        case emptyText
        case textTooLong
        case summary
        case identifier
    }

    public var id: String
    public var reason: Reason
    public var explanation: String

    public init(id: String, reason: Reason, explanation: String) {
        self.id = id
        self.reason = reason
        self.explanation = explanation
    }
}

public enum PointingActionPhase: Equatable, Sendable {
    case idle
    case confirming(PointingActionCard)
    case indicated(PointingActionIndicator)
    case refused(PointingActionRefusal)
}

/// The app's stand-in for a write. Tests pass a recorder. Production passes its own sink later.
public protocol PointingActionSink: AnyObject {
    func insertText(_ text: String)
    func writeClipboard(_ text: String)
}

/// Asks before a risky pointing action, and refuses to write into a secure field.
///
/// The proposal gate decides whether a model proposal is admissible. This type is the step
/// after that: show a card, honour cancel, and call the sink only on an accepted ordinary
/// field. It does not type, click a window, or open a link.
///
/// A text or a summary counts as present only when `PointingActionToolsBox` says it has a body.
/// A zero-width space counts. Named blanks do not. The written text stays as given.
public struct PointingActionTools: Equatable, Sendable {
    public private(set) var phase: PointingActionPhase = .idle
    private var armed: PointingActionRequest?

    public init() {}

    /// Runs one gate decision. A refusal, a guide, a host question, or an open-app
    /// decision does not touch the sink. Insert and clipboard go through `submit`.
    public mutating func offer(_ decision: PointingProposalDecision, sink: any PointingActionSink) -> PointingActionPhase {
        switch decision {
        case .proceed(let proposal, let risk):
            guard proposal.tool == .insertText, let text = proposal.arguments["text"] else { return phase }
            return submit(request(proposal, text: text, risk: risk), sink: sink)
        case .confirm(let proposal, let risk):
            guard let text = proposal.arguments["text"] else { return phase }
            switch proposal.tool {
            case .insertText, .clipboardWrite:
                return submit(request(proposal, text: text, risk: risk, kind: proposal.tool == .clipboardWrite ? .writeClipboard : .insertText), sink: sink)
            default:
                return phase
            }
        case .refused, .guide, .askHost:
            return phase
        }
    }

    private func request(_ proposal: PointingProposal, text: String, risk: DriveStep.Risk, kind: PointingActionRequest.Kind = .insertText) -> PointingActionRequest {
        let mapped: PointingActionRequest.Risk
        switch risk {
        case .safe: mapped = .safe
        case .undoable: mapped = .undoable
        case .risky: mapped = .risky
        case .destructive: mapped = .destructive
        }
        return PointingActionRequest(id: proposal.id, kind: kind, summary: proposal.summary, text: text, risk: mapped)
    }

    public mutating func submit(_ request: PointingActionRequest, sink: any PointingActionSink) -> PointingActionPhase {
        armed = nil
        if let refusal = Self.refusal(for: request) {
            phase = .refused(refusal)
            return phase
        }
        if Self.needsCard(request) {
            armed = request
            phase = .confirming(PointingActionCard(id: request.id, summary: request.summary, kind: request.kind))
            return phase
        }
        perform(request, sink: sink)
        return phase
    }

    public mutating func accept(
        _ id: String,
        focusedFieldIsSecure: Bool = false,
        sink: any PointingActionSink
    ) -> PointingActionPhase {
        guard let request = armed, request.id == id, case .confirming(let card) = phase, card.id == id else {
            return phase
        }
        if request.kind == .insertText, focusedFieldIsSecure || request.focusedFieldIsSecure {
            armed = nil
            phase = .refused(Self.secureRefusal(id: request.id))
            return phase
        }
        perform(request, sink: sink)
        return phase
    }

    public mutating func decline(_ id: String) -> PointingActionPhase {
        guard armed?.id == id, case .confirming = phase else { return phase }
        armed = nil
        phase = .idle
        return phase
    }

    public mutating func cancel(_ id: String) -> PointingActionPhase {
        guard let request = armed, request.id == id, case .confirming(let card) = phase, card.id == id else {
            return phase
        }
        armed = nil
        phase = .indicated(PointingActionIndicator(id: request.id, state: .cancelled, summary: card.summary))
        return phase
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase && lhs.armed == rhs.armed
    }

    private static let privilegedWords = ["send", "delete", "purchase", "publish"]

    private static func refusal(for request: PointingActionRequest) -> PointingActionRefusal? {
        guard validIdentifier(request.id) else {
            return PointingActionRefusal(
                id: request.id,
                reason: .identifier,
                explanation: "That action is missing a usable identifier."
            )
        }
        if request.kind == .insertText, request.focusedFieldIsSecure {
            return secureRefusal(id: request.id)
        }
        guard validSummary(request.summary) else {
            return PointingActionRefusal(
                id: request.id,
                reason: .summary,
                explanation: "That action needs a short summary before I can ask."
            )
        }
        if !PointingActionToolsBox.hasBody(request.text) {
            return PointingActionRefusal(id: request.id, reason: .emptyText, explanation: "There is no text to put there.")
        }
        if request.text.utf8.count > PointingActionRequest.maxTextBytes {
            return PointingActionRefusal(id: request.id, reason: .textTooLong, explanation: "That text is too long to put there.")
        }
        return nil
    }

    private static func secureRefusal(id: String) -> PointingActionRefusal {
        PointingActionRefusal(
            id: id,
            reason: .secureField,
            explanation: "The focused field is a password field, so I'll leave that one to you."
        )
    }

    private static func needsCard(_ request: PointingActionRequest) -> Bool {
        if request.kind == .writeClipboard { return true }
        if request.privilege != .none { return true }
        if mentionsPrivilege(request.summary) || mentionsPrivilege(request.text) { return true }
        return request.risk >= .risky
    }

    private static func mentionsPrivilege(_ text: String) -> Bool {
        let lower = text.lowercased()
        return privilegedWords.contains { lower.contains($0) }
    }

    private static func validIdentifier(_ id: String) -> Bool {
        (1...PointingActionRequest.maxIdentifierBytes).contains(id.utf8.count)
    }

    /// A body of only named blanks is empty. A zero-width space is a summary.
    private static func validSummary(_ summary: String) -> Bool {
        guard (1...PointingActionRequest.maxSummaryBytes).contains(summary.utf8.count) else { return false }
        return PointingActionToolsBox.hasBody(summary)
    }

    private mutating func perform(_ request: PointingActionRequest, sink: any PointingActionSink) {
        switch request.kind {
        case .insertText:
            sink.insertText(request.text)
        case .writeClipboard:
            sink.writeClipboard(request.text)
        }
        armed = nil
        phase = .indicated(PointingActionIndicator(id: request.id, state: .done, summary: request.summary))
    }
}
