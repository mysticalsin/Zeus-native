import Foundation

/// One agent event forwarded by `zeus-hook` to the app over the Unix socket, one JSON line each.
public struct HookEvent: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case claudeCode = "claude-code"
        case codex
        case cursor
        case gemini
    }

    public enum Risk: String, Codable, Sendable {
        case low, medium, high
    }

    public var v: Int = 1
    public let id: String
    public let source: Source
    public let event: String
    public let session: String?
    public let cwd: String?
    public let tool: String?
    public let input: JSONValue?
    public let risk: Risk?
    /// Human text from the event: the prompt, the last assistant message, or a notification.
    public let detail: String?
    public let needsDecision: Bool
    /// The terminal or editor the agent runs in (newer `zeus-hook` only).
    public var terminal: TerminalInfo?

    public init(
        id: String = UUID().uuidString,
        source: Source,
        event: String,
        session: String? = nil,
        cwd: String? = nil,
        tool: String? = nil,
        input: JSONValue? = nil,
        risk: Risk? = nil,
        detail: String? = nil,
        needsDecision: Bool,
        terminal: TerminalInfo? = nil
    ) {
        self.id = id
        self.source = source
        self.event = event
        self.session = session
        self.cwd = cwd
        self.tool = tool
        self.input = input
        self.risk = risk
        self.detail = detail
        self.needsDecision = needsDecision
        self.terminal = terminal
    }
}

public struct HookDecision: Codable, Equatable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case allow, deny, ask
    }

    public let id: String
    public let decision: Verdict
    public let reason: String?
    /// For "allow": the tool input to run instead (answers to a question, an edited command).
    public var updatedInput: JSONValue?

    public init(id: String, decision: Verdict, reason: String? = nil, updatedInput: JSONValue? = nil) {
        self.id = id
        self.decision = decision
        self.reason = reason
        self.updatedInput = updatedInput
    }

    /// The JSON Claude Code expects from a PermissionRequest hook, or nil for "ask", which
    /// means print nothing so Claude Code shows its normal permission prompt.
    public func claudePermissionRequestOutput() -> [String: JSONValue]? {
        var decisionObject: [String: JSONValue]
        switch decision {
        case .ask: return nil
        case .allow:
            decisionObject = ["behavior": .string("allow")]
            if let updatedInput { decisionObject["updatedInput"] = updatedInput }
        case .deny: decisionObject = ["behavior": .string("deny"), "message": .string(reason ?? "Denied in ZEUS")]
        }
        return ["hookSpecificOutput": .object([
            "hookEventName": .string("PermissionRequest"),
            "decision": .object(decisionObject),
        ])]
    }

    /// The JSON Claude Code expects on stdout from a PreToolUse hook.
    public func claudeCodeOutput() -> [String: JSONValue] {
        var output: [String: JSONValue] = [
            "hookEventName": .string("PreToolUse"),
            "permissionDecision": .string(decision.rawValue),
        ]
        if let reason { output["permissionDecisionReason"] = .string(reason) }
        return ["hookSpecificOutput": .object(output)]
    }
}

/// A rough risk guess shown on approval cards. The agent's own permission system stays in charge.
public enum CommandRisk {
    static let highPatterns = ["rm -rf", "rm -fr", "sudo ", "git push --force", "git push -f", "git reset --hard",
                               "mkfs", "dd if=", "chmod -R 777", "> /dev/", "curl ", "| sh", "| bash", "drop table"]
    static let mediumPatterns = ["rm ", "git push", "npm publish", "mv ", "kill ", "brew install", "pip install"]

    public static func assess(tool: String?, input: JSONValue?) -> HookEvent.Risk {
        guard let command = input?["command"]?.stringValue?.lowercased() else {
            return tool == "Bash" ? .medium : .low
        }
        if highPatterns.contains(where: command.contains) { return .high }
        if mediumPatterns.contains(where: command.contains) { return .medium }
        return .low
    }
}
