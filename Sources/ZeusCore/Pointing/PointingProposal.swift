import Foundation

/// One control the app found. The model does not invent these ids.
public struct PointingProposalCandidate: Equatable, Sendable {
    public var id: String
    public var isSecure: Bool
    public var label: String

    public init(id: String, isSecure: Bool, label: String) {
        self.id = id
        self.isSecure = isSecure
        self.label = label
    }
}

/// A proposal as the model wrote it, before the allowlist.
public struct PointingProposalDraft: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var tool: String
    public var targetID: String?
    public var arguments: [String: String]
    public var summary: String

    public init(id: String, kind: String, tool: String, targetID: String?, arguments: [String: String], summary: String) {
        self.id = id
        self.kind = kind
        self.tool = tool
        self.targetID = targetID
        self.arguments = arguments
        self.summary = summary
    }
}

/// A proposal the gate admitted. Tools outside the allowlist never become this value.
public struct PointingProposal: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case guidance, action
    }

    public enum Tool: String, Equatable, Sendable {
        case awaitClick, awaitScroll
        case openApp, openURL, clipboardWrite, insertText
    }

    public var id: String
    public var kind: Kind
    public var tool: Tool
    public var targetID: String?
    public var arguments: [String: String]
    public var summary: String

    public init(id: String, kind: Kind, tool: Tool, targetID: String?, arguments: [String: String], summary: String) {
        self.id = id
        self.kind = kind
        self.tool = tool
        self.targetID = targetID
        self.arguments = arguments
        self.summary = summary
    }
}

/// What the app may do with one proposal. A refusal does not run.
public enum PointingProposalDecision: Equatable, Sendable {
    /// Show the bolt and wait. The model is not asked again.
    case guide(PointingProposal)
    /// An action whose drive risk is safe or undoable.
    case proceed(PointingProposal, DriveStep.Risk)
    /// An action that waits for a yes. Clipboard writes always land here.
    case confirm(PointingProposal, DriveStep.Risk)
    /// An https link. The app asks the first time it sees `host`.
    case askHost(PointingProposal, host: String)
    case refused(String)
}

/// A model proposal is kept. The allowlist is not applied yet.
public enum PointingProposalGate {
    public static let maxPerEvent = 2
    public static let maxPerTurn = 4

    public static func decide(
        _ proposals: [PointingProposalDraft],
        candidates: [PointingProposalCandidate],
        focusedFieldIsSecure: Bool,
        admittedThisTurn: Int
    ) -> [PointingProposalDecision] {
        _ = candidates
        _ = focusedFieldIsSecure
        _ = admittedThisTurn
        return proposals.map { draft in
            .guide(PointingProposal(
                id: draft.id, kind: .guidance, tool: .awaitClick,
                targetID: draft.targetID, arguments: draft.arguments, summary: draft.summary
            ))
        }
    }
}
