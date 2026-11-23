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
    /// Every supported agent follows its setting. Gemini and Cursor additionally require an
    /// installed CLI. An empty selection stays empty; turning everything off must be respected.
    public static func offered(claude: Bool, codex: Bool, gemini: Bool = true, cursor: Bool = true,
                               installed: Set<CodingTool>) -> [CodingTool] {
        var list: [CodingTool] = []
        if claude { list.append(.claude) }
        if codex { list.append(.codex) }
        if gemini, installed.contains(.gemini) { list.append(.gemini) }
        if cursor, installed.contains(.cursorAgent) { list.append(.cursorAgent) }
        return list
    }

    /// The `general.defaultAgent` label ("Claude Code", "Codex") if it is offered, else the first offered.
    /// Nothing offered stays unset. A turned-off agent is not put back.
    public static func defaultTool(label: String, offered: [CodingTool]) -> CodingTool? {
        let saved = CodingTool.named(label).flatMap { offered.contains($0) ? $0.title : nil }
        guard let name = ConnectionFallback.selection(saved: saved, offered: offered.map(\.title)) else { return nil }
        return offered.first { $0.title == name }
    }
}
