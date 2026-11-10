import Foundation

/// Turns the hook payloads of Codex, Gemini CLI and cursor-agent into ZEUS's common event
/// names (Claude Code's), so one notch handles every agent.
public enum AgentHookNormalizer {
    public struct Normalized: Equatable, Sendable {
        public var event: String
        public var session: String?
        public var cwd: String?
        public var tool: String?
        public var input: JSONValue?
        public var detail: String?
        /// Only Claude Code and Codex wait for a notch decision; the others are observed.
        public var needsDecision: Bool
    }

    public static func normalize(_ payload: JSONValue, source: HookEvent.Source) -> Normalized? {
        let raw = payload["hook_event_name"]?.stringValue ?? payload["hookEventName"]?.stringValue ?? ""
        let session = payload["session_id"]?.stringValue ?? payload["conversation_id"]?.stringValue ?? payload["sessionId"]?.stringValue
        let cwd = payload["cwd"]?.stringValue ?? payload["workspace_roots"]?.arrayValue?.first?.stringValue
        let tool = payload["tool_name"]?.stringValue
        let input = payload["tool_input"]
        switch source {
        case .claudeCode, .codex:
            guard !raw.isEmpty else { return nil }
            var detail = payload["prompt"]?.stringValue ?? payload["last_assistant_message"]?.stringValue ?? payload["message"]?.stringValue
            // The question tool's result, so ZEUS can check its answers arrived.
            if raw == "PostToolUse", tool == "AskUserQuestion", let response = payload["tool_response"] {
                detail = response.stringValue ?? (try? JSONEncoder().encode(response)).map { String(decoding: $0, as: UTF8.self) }
            }
            // A turn that ended in an error: the card shows why.
            if raw == "StopFailure" { detail = AgentFailureParser.reason(from: payload) }
            return Normalized(event: raw, session: session, cwd: cwd, tool: tool, input: input, detail: detail,
                              needsDecision: raw == "PermissionRequest")
        case .gemini:
            let event: String
            switch raw {
            case "SessionStart": event = "SessionStart"
            case "SessionEnd": event = "SessionEnd"
            case "BeforeAgent": event = "UserPromptSubmit"
            case "AfterAgent": event = "Stop"
            case "BeforeTool": event = "PreToolUse"
            case "AfterTool": event = "PostToolUse"
            default: return nil
            }
            let detail = payload["prompt"]?.stringValue ?? payload["prompt_response"]?.stringValue ?? payload["response"]?.stringValue
            return Normalized(event: event, session: session, cwd: cwd, tool: tool.map(geminiTool), input: input, detail: detail, needsDecision: false)
        case .cursor:
            var event = ""
            var cursorTool: String?
            var cursorInput: JSONValue?
            switch raw {
            case "beforeSubmitPrompt": event = "UserPromptSubmit"
            case "stop": event = "Stop"
            case "beforeShellExecution", "afterShellExecution":
                event = raw.hasPrefix("before") ? "PreToolUse" : "PostToolUse"
                cursorTool = "Bash"
                cursorInput = payload["command"].map { .object(["command": $0]) }
            case "afterFileEdit":
                event = "PostToolUse"
                cursorTool = "Edit"
                cursorInput = payload["file_path"].map { .object(["file_path": $0]) }
            case "beforeMCPExecution", "afterMCPExecution":
                event = raw.hasPrefix("before") ? "PreToolUse" : "PostToolUse"
                cursorTool = payload["tool_name"]?.stringValue.map { "mcp__\($0)" } ?? "MCP"
            case "afterAgentResponse":
                // The answer text, kept for the completion card on the next "stop".
                event = "AgentResponse"
            default: return nil
            }
            let detail = payload["prompt"]?.stringValue ?? payload["text"]?.stringValue
            return Normalized(event: event, session: session, cwd: cwd, tool: cursorTool, input: cursorInput, detail: detail, needsDecision: false)
        }
    }

    /// Gemini's tool names in the words the notch already knows.
    static func geminiTool(_ name: String) -> String {
        switch name {
        case "run_shell_command": "Bash"
        case "replace", "edit": "Edit"
        case "write_file": "Write"
        case "read_file", "read_many_files": "Read"
        case "glob": "Glob"
        case "search_file_content", "grep": "Grep"
        case "web_fetch": "WebFetch"
        case "google_web_search": "WebSearch"
        default: name
        }
    }
}

/// Adds or removes ZEUS's hook command in each agent's own config file, leaving every other
/// entry (other tools' hooks, settings) as it was. Pure JSON in, JSON out, so it is tested.
public enum AgentHookConfig {
    public enum Agent: String, CaseIterable, Sendable {
        case codex, gemini, cursor

        public var title: String {
            switch self {
            case .codex: "Codex"
            case .gemini: "Gemini CLI"
            case .cursor: "Cursor Agent"
            }
        }

        /// Config file relative to the home folder.
        public var relativePath: String {
            switch self {
            case .codex: ".codex/hooks.json"
            case .gemini: ".gemini/settings.json"
            case .cursor: ".cursor/hooks.json"
            }
        }

        public var events: [String] {
            switch self {
            case .codex: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
            case .gemini: ["SessionStart", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "SessionEnd"]
            case .cursor: ["beforeSubmitPrompt", "beforeShellExecution", "afterShellExecution", "afterFileEdit",
                           "beforeMCPExecution", "afterMCPExecution", "afterAgentResponse", "stop"]
            }
        }

        var source: String {
            switch self {
            case .codex: "codex"
            case .gemini: "gemini"
            case .cursor: "cursor"
            }
        }
    }

    /// Guarded like the Claude Code hook: if ZEUS is removed, the agent carries on silently.
    public static func command(helper: String, agent: Agent) -> String {
        "/bin/sh -c '[ -x \"\(helper)\" ] && \"\(helper)\" --source \(agent.source) || true'"
    }

    static func isOurs(_ command: String?) -> Bool {
        command?.contains("zeus-hook") == true
    }

    /// The config with ZEUS's hook on every event the agent supports (idempotent).
    public static func install(into config: JSONValue?, agent: Agent, helper: String) -> JSONValue {
        let cleaned = uninstall(from: config, agent: agent)
        var root: [String: JSONValue] = if case .object(let value) = cleaned { value } else { [:] }
        var hooks: [String: JSONValue] = if case .object(let value)? = root["hooks"] { value } else { [:] }
        let command = command(helper: helper, agent: agent)
        for event in agent.events {
            var entries = hooks[event]?.arrayValue ?? []
            switch agent {
            case .codex:
                // Claude Code's shape: [{matcher?, hooks: [{type, command, timeout}]}]
                let timeout: Double = event == "PermissionRequest" ? 120 : 5
                entries.append(.object(["hooks": .array([.object(["type": .string("command"), "command": .string(command), "timeout": .number(timeout)])])]))
            case .gemini:
                entries.append(.object(["hooks": .array([.object(["type": .string("command"), "command": .string(command), "timeout": .number(5000)])])]))
            case .cursor:
                entries.append(.object(["command": .string(command)]))
            }
            hooks[event] = .array(entries)
        }
        root["hooks"] = .object(hooks)
        if agent == .cursor, root["version"] == nil { root["version"] = .number(1) }
        return .object(root)
    }

    /// The config without ZEUS's hooks; events left empty are removed.
    public static func uninstall(from config: JSONValue?, agent: Agent) -> JSONValue {
        guard case .object(var root)? = config else { return config ?? .object([:]) }
        guard case .object(var hooks)? = root["hooks"] else { return .object(root) }
        for (event, value) in hooks {
            guard let entries = value.arrayValue else { continue }
            let kept: [JSONValue] = entries.compactMap { entry in
                if isOurs(entry["command"]?.stringValue) { return nil }
                guard let inner = entry["hooks"]?.arrayValue else { return entry }
                let remaining = inner.filter { !isOurs($0["command"]?.stringValue) }
                if remaining.isEmpty { return nil }
                guard case .object(var object) = entry else { return entry }
                object["hooks"] = .array(remaining)
                return .object(object)
            }
            hooks[event] = kept.isEmpty ? nil : .array(kept)
        }
        root["hooks"] = .object(hooks)
        return .object(root)
    }

    public static func isInstalled(in config: JSONValue?, agent: Agent) -> Bool {
        guard let hooks = config?["hooks"] else { return false }
        return agent.events.contains { event in
            (hooks[event]?.arrayValue ?? []).contains { entry in
                isOurs(entry["command"]?.stringValue) || (entry["hooks"]?.arrayValue ?? []).contains { isOurs($0["command"]?.stringValue) }
            }
        }
    }
}

/// Follows Codex sessions from their rollout logs when ZEUS's Codex hooks are not installed:
/// one small state per file, updated from appended lines only.
public struct CodexRolloutWatch: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case started(cwd: String?)
        case prompt(String)
        case tool(String)
        case finished(String?)
        case failed(String)
    }

    public var session: String?
    public var cwd: String?
    public var working = false

    public init() {}

    /// Applies one line and reports what changed for the notch.
    public mutating func apply(line: Data) -> Change? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return nil }
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("session_meta", _):
            session = payload["session_id"] as? String ?? payload["id"] as? String
            cwd = payload["cwd"] as? String ?? cwd
            return .started(cwd: cwd)
        case ("turn_context", _):
            if let directory = payload["cwd"] as? String { cwd = directory }
            return nil
        case ("event_msg", "user_message"):
            working = true
            return .prompt(payload["message"] as? String ?? "working")
        case ("event_msg", "item_completed"):
            guard let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage" else { return nil }
            working = true
            let text = (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ")
            return .prompt(text?.isEmpty == false ? text! : "working")
        case ("event_msg", "task_started"):
            working = true
            return nil
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"), ("response_item", "local_shell_call"):
            return working ? .tool(payload["name"] as? String ?? "shell") : nil
        case ("event_msg", "error"):
            working = false
            return .failed(AgentFailureParser.reason(code: payload["codex_error_info"] as? String, detail: payload["message"] as? String))
        case ("event_msg", "task_complete"):
            working = false
            return .finished(payload["last_agent_message"] as? String)
        default:
            return nil
        }
    }
}
