import Foundation

/// The notch's New chat flow: which agents are offered, the default, and the request that starts one
/// through the same terminal path as the `terminal.agent` action.
public struct NewChatRequest: Equatable, Sendable {
    public var tool: CodingTool
    public var directory: String
    public var instruction: String

    public init(tool: CodingTool, directory: String, instruction: String) {
        self.tool = tool; self.directory = directory; self.instruction = instruction
    }

    public var cleanedInstruction: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool { !cleanedInstruction.isEmpty && !directory.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The action the app performs: identical to what a spoken "ask codex to ..." produces.
    public var command: CodeCommand? {
        guard isValid else { return nil }
        return .agent(tool: tool, project: nil, dir: directory, task: cleanedInstruction)
    }

    public func job(binaryPath: String? = nil) -> TerminalJob {
        TerminalJob.agent(tool, task: cleanedInstruction, directory: directory, binaryPath: binaryPath)
    }
}

public enum NewChatAgents {
    /// Claude Code and Codex follow their Settings > Integrations toggles; Gemini and Cursor show
    /// when their CLI is installed. Never empty: Claude Code is the fallback.
    public static func offered(claude: Bool, codex: Bool, installed: Set<CodingTool>) -> [CodingTool] {
        var list: [CodingTool] = []
        if claude { list.append(.claude) }
        if codex { list.append(.codex) }
        for tool in [CodingTool.gemini, .cursorAgent] where installed.contains(tool) { list.append(tool) }
        return list.isEmpty ? [.claude] : list
    }

    /// The `general.defaultAgent` label ("Claude Code", "Codex") if it is offered, else the first offered.
    public static func defaultTool(label: String, offered: [CodingTool]) -> CodingTool {
        if let tool = CodingTool.named(label), offered.contains(tool) { return tool }
        return offered.first ?? .claude
    }
}
