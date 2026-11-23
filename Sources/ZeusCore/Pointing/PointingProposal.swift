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

/// Allowlist for one model turn. At most two proposals in an event and four in the turn.
public enum PointingProposalGate {
    public static let maxPerEvent = 2
    public static let maxPerTurn = 4

    public static func decide(
        _ proposals: [PointingProposalDraft],
        candidates: [PointingProposalCandidate],
        focusedFieldIsSecure: Bool,
        admittedThisTurn: Int
    ) -> [PointingProposalDecision] {
        if proposals.count > maxPerEvent {
            return Array(repeating: .refused("event limit"), count: proposals.count)
        }
        var admitted = max(0, admittedThisTurn)
        var seen = Set<String>()
        return proposals.map { draft in
            let decision = one(draft, candidates: candidates, focusedFieldIsSecure: focusedFieldIsSecure, seen: &seen)
            switch decision {
            case .refused:
                return decision
            case .guide, .proceed, .confirm, .askHost:
                guard admitted < maxPerTurn else { return .refused("turn limit") }
                admitted += 1
                return decision
            }
        }
    }

    private static func one(
        _ draft: PointingProposalDraft,
        candidates: [PointingProposalCandidate],
        focusedFieldIsSecure: Bool,
        seen: inout Set<String>
    ) -> PointingProposalDecision {
        guard identifier(draft.id) else { return .refused("identifier") }
        guard seen.insert(draft.id).inserted else { return .refused("identifier") }
        guard kinds.contains(draft.kind) else { return .refused("kind") }
        guard tools.contains(draft.tool) else { return .refused("tool") }
        guard let paired = pair(kind: draft.kind, tool: draft.tool) else { return .refused("pairing") }
        guard summary(draft.summary) else { return .refused("summary") }
        guard Set(draft.arguments.keys) == argumentKeys(paired.tool) else { return .refused("arguments") }

        let candidate: PointingProposalCandidate?
        if let targetID = draft.targetID {
            guard self.targetID(targetID), let match = candidates.first(where: { $0.id == targetID }) else {
                return .refused("target")
            }
            candidate = match
        } else {
            candidate = nil
        }
        if paired.kind == .action, let candidate, candidate.isSecure {
            return .refused("secure")
        }

        let proposal = PointingProposal(
            id: draft.id, kind: paired.kind, tool: paired.tool,
            targetID: draft.targetID, arguments: draft.arguments, summary: draft.summary
        )
        switch paired.tool {
        case .awaitClick:
            guard candidate != nil else { return .refused("target") }
            return .guide(proposal)
        case .awaitScroll:
            return .guide(proposal)
        case .openApp:
            guard let bundle = draft.arguments["bundleID"], bundleID(bundle) else { return .refused("bundle") }
            return .proceed(proposal, DriveStep.openApp(bundle).risk)
        case .openURL:
            guard let raw = draft.arguments["url"], let host = httpsHost(raw) else { return .refused("url") }
            return .askHost(proposal, host: host)
        case .clipboardWrite:
            guard let text = draft.arguments["text"], boundedText(text, maximum: 2000) else { return .refused("arguments") }
            return .confirm(proposal, DriveStep.writeClipboard(text).risk)
        case .insertText:
            guard let text = draft.arguments["text"], boundedText(text, maximum: 2000) else { return .refused("arguments") }
            if focusedFieldIsSecure { return .refused("secure") }
            if let candidate, DriveStep.looksSecret(DriveTarget(label: candidate.label)) { return .refused("secret") }
            if DriveStep.looksSecret(DriveTarget(label: text)) { return .refused("secret") }
            if text.contains("\n") || text.contains("\r") { return .refused("return") }
            if DriveStep.isDestructive(text) || DriveStep.isDestructive(candidate?.label) {
                return .confirm(proposal, .destructive)
            }
            let risk = DriveStep.type(text, into: DriveTarget(label: candidate?.label)).risk
            return risk >= .risky ? .confirm(proposal, risk) : .proceed(proposal, risk)
        }
    }

    private static let kinds: Set<String> = ["guidance", "action"]
    private static let tools: Set<String> = [
        "awaitClick", "awaitScroll", "openApp", "openURL", "clipboardWrite", "insertText",
    ]

    private static func pair(kind: String, tool: String) -> (kind: PointingProposal.Kind, tool: PointingProposal.Tool)? {
        switch (kind, tool) {
        case ("guidance", "awaitClick"): return (.guidance, .awaitClick)
        case ("guidance", "awaitScroll"): return (.guidance, .awaitScroll)
        case ("action", "openApp"): return (.action, .openApp)
        case ("action", "openURL"): return (.action, .openURL)
        case ("action", "clipboardWrite"): return (.action, .clipboardWrite)
        case ("action", "insertText"): return (.action, .insertText)
        default: return nil
        }
    }

    private static func argumentKeys(_ tool: PointingProposal.Tool) -> Set<String> {
        switch tool {
        case .awaitClick, .awaitScroll: return []
        case .openApp: return ["bundleID"]
        case .openURL: return ["url"]
        case .clipboardWrite, .insertText: return ["text"]
        }
    }

    private static func identifier(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return (1...64).contains(bytes.count) && bytes.allSatisfy(isIdentifierByte)
    }

    /// `^t[0-9]{1,2}$`
    private static func targetID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        return (2...3).contains(bytes.count) && bytes[0] == 116 && bytes.dropFirst().allSatisfy { (48...57).contains($0) }
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 95
    }

    private static func summary(_ text: String) -> Bool {
        guard (1...200).contains(text.utf8.count) else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value >= 32 && value != 127
        }
    }

    private static func boundedText(_ text: String, maximum: Int) -> Bool {
        guard text.utf8.count <= maximum else { return false }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            if value == 9 || value == 10 || value == 13 { return true }
            return value >= 32 && value != 127
        }
    }

    private static func bundleID(_ raw: String) -> Bool {
        guard (1...255).contains(raw.utf8.count) else { return false }
        let pattern = #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"#
        return raw.range(of: pattern, options: .regularExpression) != nil
    }

    /// https only. No user info, and no `file:`, `javascript:`, or other scheme.
    private static func httpsHost(_ raw: String) -> String? {
        guard raw.utf8.count <= 2048, !raw.contains(where: \.isWhitespace) else { return nil }
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.user == nil,
              let host = url.host, !host.isEmpty else { return nil }
        return host
    }
}
