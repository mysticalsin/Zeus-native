import Foundation

/// The coding agent CLIs Zeus can start in a terminal for Tony.
///
/// These are Tony's own coding sessions. The CLI runs with ITS user defaults (its model, effort
/// and permissions, as in any terminal he opens himself). `ModelCap` applies only to Zeus's own
/// brain calls (voice turns, the browser agent, research), never to the sessions started here.
/// The agent hooks then show the session in the notch like any other.
public enum CodingTool: String, CaseIterable, Codable, Sendable {
    case claude, codex, gemini
    case cursorAgent = "cursor-agent"

    public var binary: String { rawValue }

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursorAgent: "Cursor Agent"
        }
    }

    /// Spoken names and spellings → tool: "claude", "claude code", "cursor", "cursor agent".
    public static func named(_ text: String) -> CodingTool? {
        switch AppMatcher.normalize(text) {
        case "claude", "claude code", "claudecode", "clode", "cloud code": .claude
        case "codex", "codecs", "codex cli": .codex
        case "gemini", "gemini cli", "jemini": .gemini
        case "cursor", "cursor agent", "cursor cli", "cursor agent cli": .cursorAgent
        default: nil
        }
    }

    /// The argument list that starts an interactive session whose first prompt is `task`.
    /// A task that starts with "-" would be read as an option, so it gets a lead-in word.
    public func arguments(task: String) -> [String] {
        let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let prompt = text.hasPrefix("-") ? "Task: " + text : text
        switch self {
        case .claude, .codex, .cursorAgent: return [prompt]
        case .gemini: return ["-i", prompt]
        }
    }

    public static let preferenceKey = "code.tool"

    /// Tony's preferred coding agent (Settings › Intelligence); Claude Code by default.
    public static func preferred(defaults: UserDefaults = .standard) -> CodingTool {
        defaults.string(forKey: preferenceKey).flatMap(CodingTool.init(rawValue:)) ?? .claude
    }
}

/// The terminal apps Zeus can open a session in.
public enum TerminalApp: String, CaseIterable, Codable, Sendable {
    case ghostty, iterm, warp, terminal

    public var bundleID: String {
        switch self {
        case .ghostty: "com.mitchellh.ghostty"
        case .iterm: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .terminal: "com.apple.Terminal"
        }
    }

    public var title: String {
        switch self {
        case .ghostty: "Ghostty"
        case .iterm: "iTerm"
        case .warp: "Warp"
        case .terminal: "Terminal"
        }
    }

    /// The app name `open -a` takes.
    public var openName: String {
        switch self {
        case .iterm: "iTerm"
        default: title
        }
    }

    public static let preferenceKey = "code.terminal"

    /// Which terminal to open. A choice in Settings wins ("auto" or nothing means detect). Then
    /// the one Tony has open (the front app first, then the others in this order; Terminal last,
    /// since it is often open by accident), then a non-Terminal app that opens .command files,
    /// then an installed one (Ghostty, iTerm, Warp), and Terminal as the fallback.
    public static func choose(preference: String?, frontmost: String?, running: [String], commandHandler: String?,
                              installed: Set<String>) -> TerminalApp {
        if let preference, let chosen = TerminalApp(rawValue: preference) { return chosen }
        let known = Dictionary(uniqueKeysWithValues: allCases.map { ($0.bundleID, $0) })
        if let frontmost, let app = known[frontmost] { return app }
        for app in [TerminalApp.ghostty, .iterm, .warp, .terminal] where running.contains(app.bundleID) { return app }
        if let handler = commandHandler, let app = known[handler], app != .terminal { return app }
        for app in [TerminalApp.ghostty, .iterm, .warp] where installed.contains(app.bundleID) { return app }
        return .terminal
    }
}

/// What to run in a new terminal: a plain shell in `directory`, or `commandLine` first.
public struct TerminalJob: Equatable, Sendable {
    public var directory: String
    /// A ready-to-run command line (already quoted), or nil for a plain shell.
    public var commandLine: String?
    public var title: String

    public init(directory: String, commandLine: String? = nil, title: String = "Zeus") {
        self.directory = directory; self.commandLine = commandLine; self.title = title
    }

    /// An agent session: `claude '<task>'` with every piece quoted. `binaryPath` is the CLI's
    /// absolute path when it is known (a login shell may not have it on its PATH).
    public static func agent(_ tool: CodingTool, task: String, directory: String, binaryPath: String? = nil) -> TerminalJob {
        let program = ShellQuote.single(binaryPath ?? tool.binary)
        let words = [program] + tool.arguments(task: task).map(ShellQuote.single)
        return TerminalJob(directory: directory, commandLine: words.joined(separator: " "), title: tool.title)
    }

    /// A command Tony (or the LLM) asked to run; `command` is shell text and so must already
    /// have passed `ShellRisk` and, when it asked for it, Tony's approval.
    public static func command(_ command: String, directory: String) -> TerminalJob {
        TerminalJob(directory: directory, commandLine: command, title: "Zeus")
    }
}

/// The shell script a terminal runs, and the steps that open it. Pure: the app writes the file
/// and runs the steps, so tests need no terminal.
public enum TerminalScript {
    /// The `.command` script: go to the folder, run the command, then stay in a shell so the
    /// window doesn't vanish when the agent exits. It deletes itself (and `cleanup` files) first.
    public static func contents(for job: TerminalJob, scriptPath: String, cleanup: [String] = []) -> String {
        var lines = [
            "#!/bin/zsh -il",
            "# Written by Zeus. Deletes itself.",
            "rm -f -- \(([scriptPath] + cleanup).map(ShellQuote.single).joined(separator: " "))",
            "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"",
            "cd -- \(ShellQuote.single(job.directory)) || { echo \"Zeus: can't open that folder.\"; exec \"$SHELL\" -l; }",
            "printf '\\033]0;%s\\007' \(ShellQuote.single(job.title))",
        ]
        if let command = job.commandLine { lines.append(command) }
        lines.append("exec \"$SHELL\" -l")
        return lines.joined(separator: "\n") + "\n"
    }

    /// One step of opening a terminal.
    public enum Step: Equatable, Sendable {
        case writeFile(path: String, contents: String)
        case run(executable: String, arguments: [String])
    }

    /// Steps that open `scriptPath` (already written, executable) in `app`.
    /// Terminal and iTerm open .command files themselves; Ghostty runs it as its command; Warp
    /// gets a launch configuration (`~/.warp/launch_configurations`) and its `warp://launch` link.
    public static func steps(app: TerminalApp, scriptPath: String, directory: String, token: String,
                             home: String = NSHomeDirectory()) -> [Step] {
        switch app {
        case .terminal, .iterm:
            return [.run(executable: "/usr/bin/open", arguments: ["-a", app.openName, scriptPath])]
        case .ghostty:
            return [.run(executable: "/usr/bin/open", arguments: ["-na", "Ghostty", "--args", "-e", "/bin/zsh", scriptPath])]
        case .warp:
            let name = "zeus-\(token)"
            let yaml = """
            ---
            name: "\(ShellQuote.yaml(name))"
            windows:
              - tabs:
                  - title: "Zeus"
                    layout:
                      cwd: "\(ShellQuote.yaml(directory))"
                      commands:
                        - exec: "\(ShellQuote.yaml("/bin/zsh " + ShellQuote.single(scriptPath)))"

            """
            return [
                .writeFile(path: warpConfigPath(name: name, home: home), contents: yaml),
                .run(executable: "/usr/bin/open", arguments: ["warp://launch/\(name)"]),
            ]
        }
    }

    public static func warpConfigPath(name: String, home: String = NSHomeDirectory()) -> String {
        "\(home)/.warp/launch_configurations/\(name).yaml"
    }
}
