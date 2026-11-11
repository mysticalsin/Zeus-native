import AppKit
import ZeusCore

/// Carries out the terminal and research commands, from the fast path, the LLM's action tags and the
/// `zeus` CLI alike: a plain terminal, a coding agent in a project, a shell command (asking first
/// when it is destructive, networked or unfamiliar), and research.
@MainActor
final class CodeActions {
    static let shared = CodeActions()

    weak var notch: NotchController?
    /// Speaks and captions a line (VoiceTurnController.say).
    var say: (String) -> Void = { _ in }

    struct Result {
        var message: String
        var ok = true
    }

    // MARK: Where

    enum Folder {
        case found(URL, name: String?)
        case problem(String)
    }

    /// The folder for a project name or path and/or an explicit `dir`; home when neither is given.
    func folder(project: String?, dir: String?) -> Folder {
        if let dir {
            guard let url = ProjectScanner.existingFolder(dir) else { return .problem("I can't find the folder \(dir).") }
            return .found(url, name: nil)
        }
        guard let project else { return .found(FileManager.default.homeDirectoryForCurrentUser, name: nil) }
        if let url = ProjectScanner.existingFolder(project) { return .found(url, name: url.lastPathComponent) }
        switch ProjectScanner.shared.lookup(project) {
        case .project(let entry): return .found(URL(fileURLWithPath: entry.path, isDirectory: true), name: entry.name)
        case .ambiguous(let a, let b): return .problem("Did you mean \(a.name) or \(b.name)?")
        case .none: return .problem("I couldn't find a project called \(project).")
        }
    }

    // MARK: Commands

    func perform(_ command: CodeCommand, speak: Bool) async -> Result {
        switch command {
        case .agent(let tool, let project, let dir, let task):
            return await startAgent(tool: tool, project: project, dir: dir, task: task)
        case .openTerminal(let project, let dir):
            return await openTerminal(project: project, dir: dir)
        case .run(let shell, let dir):
            return await run(shell, dir: dir, speak: speak)
        case .research(let question, let depth):
            guard let outcome = await ResearchRunner.shared.start(question: question, depth: depth, speak: speak) else {
                return Result(message: "I'm already researching something. Stop it first.", ok: false)
            }
            return Result(message: outcome.spoken, ok: outcome.problem == nil && !outcome.cancelled)
        }
    }

    func openTerminal(project: String?, dir: String?) async -> Result {
        let (url, name): (URL, String?)
        switch folder(project: project, dir: dir) {
        case .problem(let text): return Result(message: text, ok: false)
        case .found(let found, let foundName): (url, name) = (found, foundName)
        }
        let (app, problem) = await TerminalLauncher.launch(TerminalJob(directory: url.path))
        if let problem { return Result(message: problem, ok: false) }
        return Result(message: "Opened \(app.title) in \(name ?? ProjectIndex.tilde(url.path)).")
    }

    /// Starts Tony's coding agent in the project, with `task` as its first prompt. These are his own sessions:
    /// the CLI runs with ITS user defaults. `ModelCap` only pins Zeus's own brain calls (voice,
    /// browser agent, research), never a session started here. The agent hooks show it in the notch.
    func startAgent(tool requested: CodingTool?, project: String?, dir: String?, task: String) async -> Result {
        let tool = requested ?? CodingTool.preferred()
        guard let binary = CLILocator.tools.first(where: { $0.name == tool.binary }).flatMap(CLILocator.locate) else {
            return Result(message: "\(tool.title) isn't installed.", ok: false)
        }
        let (url, name): (URL, String?)
        switch folder(project: project, dir: dir) {
        case .problem(let text): return Result(message: text, ok: false)
        case .found(let found, let foundName): (url, name) = (found, foundName)
        }
        let job = TerminalJob.agent(tool, task: task, directory: url.path, binaryPath: binary)
        let (app, problem) = await TerminalLauncher.launch(job)
        if let problem { return Result(message: problem, ok: false) }
        return Result(message: "Started \(tool.title) in \(name ?? ProjectIndex.tilde(url.path)) with \(app.title).")
    }

    /// A shell command in a visible terminal. Read-only and local build commands run at once;
    /// everything else (deleting, overwriting, installing, the network, sudo, unknown programs)
    /// waits for Tony's yes on a notch card first.
    func run(_ shell: String, dir: String?, speak: Bool) async -> Result {
        let url: URL
        switch folder(project: nil, dir: dir) {
        case .problem(let text): return Result(message: text, ok: false)
        case .found(let found, _): url = found
        }
        if let reason = HandsBlocklist.reason(shell) {
            HandsCommandLogger.append(command: shell, verdict: "blocked", outcome: reason)
            return Result(message: reason, ok: false)
        }
        let assessment = ShellRiskClassifier.assess(shell)
        if assessment.needsApproval {
            guard let notch else { return Result(message: "I can't ask you about that command yet, so I left it.", ok: false) }
            if speak { say(ZeusVoiceLines.line(for: .approval, context: ["agent": "Zeus"])) }
            let verdict = await notch.requestApproval(
                agent: "Zeus", project: ProjectIndex.tilde(url.path), tool: "Terminal",
                command: "\(shell)  (\(assessment.summary))", risk: assessment.cardRisk, timeout: .seconds(90), onTimeout: .deny)
            guard verdict == .allow else { return Result(message: "Okay, I won't run it.", ok: false) }
        }
        let (app, problem) = await TerminalLauncher.launch(.command(shell, directory: url.path))
        if let problem { return Result(message: problem, ok: false) }
        return Result(message: "Running it in \(app.title).")
    }
}
