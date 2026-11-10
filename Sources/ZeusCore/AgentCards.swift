import Foundation

// MARK: Questions (Claude Code AskUserQuestion)

/// One multiple-choice question an agent asks, answered from the notch.
public struct AgentQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        public var detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
        }
    }

    public var question: String
    public var header: String?
    public var options: [Option]
    public var multiSelect: Bool

    public init(question: String, header: String? = nil, options: [Option], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }

    /// The questions in an `AskUserQuestion` tool input; empty when the input has another shape.
    public static func parse(_ input: JSONValue?) -> [AgentQuestion] {
        (input?["questions"]?.arrayValue ?? []).compactMap { item in
            guard let question = item["question"]?.stringValue, !question.isEmpty else { return nil }
            let options = (item["options"]?.arrayValue ?? []).compactMap { option -> Option? in
                guard let label = option["label"]?.stringValue ?? option.stringValue else { return nil }
                return Option(label: label, detail: option["description"]?.stringValue)
            }
            let multi: Bool = if case .bool(let value)? = item["multiSelect"] { value } else { false }
            return AgentQuestion(question: question, header: item["header"]?.stringValue, options: options, multiSelect: multi)
        }
    }

    /// The tool input with the person's answers added (`answers: {question: "A, B"}`), which is
    /// what Claude Code reads back when the question is answered outside the terminal.
    public static func answeredInput(_ input: JSONValue?, answers: [String: [String]]) -> JSONValue {
        var object: [String: JSONValue] = if case .object(let value)? = input { value } else { [:] }
        var answered: [String: JSONValue] = [:]
        for (question, labels) in answers where !labels.isEmpty {
            answered[question] = .string(labels.joined(separator: ", "))
        }
        object["answers"] = .object(answered)
        return .object(object)
    }
}

// MARK: Plans (Claude Code ExitPlanMode)

public enum AgentPlan {
    /// The Markdown plan in an `ExitPlanMode` input.
    public static func text(_ input: JSONValue?) -> String? {
        let plan = input?["plan"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan?.isEmpty == false ? plan : nil
    }

    /// What Claude reads when the plan is sent back for more work.
    public static func feedbackMessage(_ feedback: String) -> String {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "The user did not approve this plan yet. Keep planning and ask what to change."
            : "The user did not approve this plan yet. Revise it with this feedback: \(trimmed)"
    }
}

// MARK: Diffs (Edit, MultiEdit, Write)

/// A compact line diff of a file edit, for the approval card.
public struct FileDiff: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case context, added, removed }

    public struct Line: Equatable, Sendable {
        public var kind: Kind
        public var text: String
    }

    public var path: String
    public var lines: [Line]
    public var added: Int
    public var removed: Int
    /// Lines left out to keep the card small.
    public var hiddenLines: Int
    public var isNewFile: Bool

    public var fileName: String { URL(fileURLWithPath: path).lastPathComponent }

    /// Builds the diff for an edit tool's input; nil for other tools.
    public static func from(tool: String?, input: JSONValue?, maxLines: Int = 12) -> FileDiff? {
        guard let path = input?["file_path"]?.stringValue else { return nil }
        var pairs: [(old: String, new: String)] = []
        var isNew = false
        switch tool {
        case "Edit":
            pairs = [(input?["old_string"]?.stringValue ?? "", input?["new_string"]?.stringValue ?? "")]
        case "MultiEdit":
            pairs = (input?["edits"]?.arrayValue ?? []).map { ($0["old_string"]?.stringValue ?? "", $0["new_string"]?.stringValue ?? "") }
        case "Write":
            pairs = [("", input?["content"]?.stringValue ?? "")]
            isNew = true
        default:
            return nil
        }
        var lines: [Line] = []
        for pair in pairs { lines += diff(old: split(pair.old), new: split(pair.new)) }
        let added = lines.filter { $0.kind == .added }.count
        let removed = lines.filter { $0.kind == .removed }.count
        let shown = trimContext(lines)
        return FileDiff(path: path, lines: Array(shown.prefix(maxLines)), added: added, removed: removed,
                        hiddenLines: max(shown.count - maxLines, 0), isNewFile: isNew)
    }

    static func split(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    /// Line diff by longest common subsequence.
    static func diff(old: [String], new: [String]) -> [Line] {
        let n = old.count, m = new.count
        // Large inputs: show the replacement without aligning (keeps the card instant).
        guard n * m <= 250_000 else {
            return old.map { Line(kind: .removed, text: $0) } + new.map { Line(kind: .added, text: $0) }
        }
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var lines: [Line] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] {
                lines.append(Line(kind: .context, text: old[i])); i += 1; j += 1
            } else if i < n, j == m || lcs[i + 1][j] >= lcs[i][j + 1] {
                lines.append(Line(kind: .removed, text: old[i])); i += 1
            } else {
                lines.append(Line(kind: .added, text: new[j])); j += 1
            }
        }
        return lines
    }

    /// Keeps one line of context around changes and drops the rest.
    static func trimContext(_ lines: [Line]) -> [Line] {
        let changed = Set(lines.indices.filter { lines[$0].kind != .context })
        guard !changed.isEmpty else { return lines }
        return lines.indices.filter { index in
            lines[index].kind != .context || changed.contains(index - 1) || changed.contains(index + 1)
        }.map { lines[$0] }
    }
}

// MARK: Terminal jump

/// Where an agent session runs, captured by `zeus-hook` from its environment, so a card can
/// bring that terminal or editor forward.
public struct TerminalInfo: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var program: String?
    public var sessionID: String?
    public var tty: String?

    public init(bundleID: String? = nil, program: String? = nil, sessionID: String? = nil, tty: String? = nil) {
        self.bundleID = bundleID
        self.program = program
        self.sessionID = sessionID
        self.tty = tty
    }

    /// Reads the variables terminals and editors set for their child processes.
    public static func from(environment env: [String: String]) -> TerminalInfo? {
        let info = TerminalInfo(
            bundleID: env["__CFBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 },
            program: env["TERM_PROGRAM"],
            sessionID: env["ITERM_SESSION_ID"] ?? env["TERM_SESSION_ID"],
            tty: nil
        )
        return info.bundleID == nil && info.program == nil ? nil : info
    }

    static let programBundles: [String: String] = [
        "apple_terminal": "com.apple.Terminal",
        "iterm.app": "com.googlecode.iterm2",
        "ghostty": "com.mitchellh.ghostty",
        "warpterminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "wezterm": "com.github.wez.wezterm",
        "tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
        "zed": "dev.zed.Zed",
    ]

    /// The app to bring forward: the launching app's bundle ID, else one known for TERM_PROGRAM.
    public var targetBundleID: String? {
        if let bundleID { return bundleID }
        guard let program = program?.lowercased() else { return nil }
        return Self.programBundles[program]
    }
}

// MARK: Completion and quiet mode

/// The card shown when an agent finishes a turn.
public struct AgentCompletion: Equatable, Sendable {
    public var sessionID: String
    public var agent: String
    public var project: String
    public var summary: String
    public var duration: TimeInterval?

    public init(sessionID: String, agent: String, project: String, summary: String?, startedAt: Date?, now: Date = Date()) {
        self.sessionID = sessionID
        self.agent = agent
        self.project = project
        let text = (summary ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        self.summary = text.isEmpty ? "Finished." : (text.count > 160 ? String(text.prefix(159)) + "…" : text)
        duration = startedAt.map { now.timeIntervalSince($0) }
    }

    /// "4 min", "38 s", "1 h 05 min".
    public static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        if total < 3600 { return "\(total / 60) min" }
        return String(format: "%d h %02d min", total / 3600, (total % 3600) / 60)
    }
}

/// What ZEUS shows while a full-screen app (a film, a game, a presentation) is in front.
public enum AgentQuietPolicy {
    public enum Event: Sendable { case peek, completion, approval, question }

    public struct Outcome: Equatable, Sendable {
        public var present: Bool
        public var sound: Bool
    }

    /// Decisions the agent is blocked on still appear, without sound; everything else waits.
    public static func outcome(for event: Event, fullScreen: Bool, quietEnabled: Bool, soundsEnabled: Bool) -> Outcome {
        guard fullScreen, quietEnabled else {
            return Outcome(present: true, sound: soundsEnabled && event != .peek)
        }
        switch event {
        case .approval, .question: return Outcome(present: true, sound: false)
        case .peek, .completion: return Outcome(present: false, sound: false)
        }
    }
}
