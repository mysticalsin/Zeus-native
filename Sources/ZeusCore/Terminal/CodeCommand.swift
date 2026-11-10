import Foundation

/// The typed view of the terminal and research action tags (`terminal.agent`, `terminal.open`,
/// `terminal.run`, `research`), the way `BrowserCommand` is for the browser ones.
///
///   [ACTION:{"type":"terminal.agent","tool":"codex","project":"zeus","task":"fix the failing tests"}]
///   [ACTION:{"type":"terminal.open","project":"polyglot"}]            (or "dir":"~/dev/x")
///   [ACTION:{"type":"terminal.run","command":"git status","dir":"~/dev/zeus"}]
///   [ACTION:{"type":"research","question":"…","depth":"quick"}]       ("deep" for a thorough one)
public enum CodeCommand: Equatable, Sendable {
    case agent(tool: CodingTool?, project: String?, dir: String?, task: String)
    case openTerminal(project: String?, dir: String?)
    case run(command: String, dir: String?)
    case research(question: String, depth: ResearchDepth)

    public init?(_ action: ZeusAction) {
        func text(_ key: String) -> String? {
            let value = action.payload[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty ?? true) ? nil : value
        }
        switch action.kind {
        case .terminalAgent:
            guard let task = text("task") else { return nil }
            self = .agent(tool: text("tool").flatMap(CodingTool.named), project: text("project"), dir: text("dir"), task: task)
        case .terminalOpen:
            self = .openTerminal(project: text("project"), dir: text("dir"))
        case .terminalRun:
            guard let command = text("command") else { return nil }
            self = .run(command: command, dir: text("dir"))
        case .research:
            guard let question = text("question") ?? text("topic") else { return nil }
            self = .research(question: question, depth: text("depth").flatMap(ResearchDepth.init(rawValue:)) ?? .quick)
        default:
            return nil
        }
    }

    /// For logs and the CLI's "action:" lines.
    public var label: String {
        switch self {
        case .agent(let tool, let project, _, let task): "terminal agent \(tool?.title ?? "default")\(project.map { " in \($0)" } ?? ""): \(task.prefix(60))"
        case .openTerminal(let project, _): "terminal\(project.map { " in \($0)" } ?? "")"
        case .run(let command, _): "terminal run: \(command.prefix(60))"
        case .research(let question, let depth): "research (\(depth.rawValue)): \(question.prefix(60))"
        }
    }

    /// "~/dev/zeus" → an absolute path; nil when it isn't a path.
    public static func expandPath(_ text: String, home: String = NSHomeDirectory()) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home + "/" + trimmed.dropFirst(2) }
        return trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed).standardizedFileURL.path : nil
    }
}
