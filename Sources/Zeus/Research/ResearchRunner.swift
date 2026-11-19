import AppKit
import ZeusCore

/// A research turn: a headless brain run with web tools on, a notch card ("Researching …", with
/// Stop), a one or two sentence spoken answer in the persona, and the full report with sources saved
/// as markdown (ZEUS/Research/<date> <title>.md in the second brain, else ~/Documents/Zeus Research)
/// and shown in Chat.
///
/// This is Zeus's own brain call, so `ModelCap` pins the model: Haiku for quick, Sonnet (never
/// larger) for deep. Claude runs with `--allowedTools WebSearch,WebFetch`; Gemini uses its built-in
/// Google Search. Codex and Cursor Agent have no web tool we can rely on, so the order is the preferred
/// web engine, then the other, and last the browser agent reading the top search results.
@MainActor
final class ResearchRunner {
    static let shared = ResearchRunner()
    static let sessionID = "zeus-research"

    weak var notch: NotchController?
    var say: (String) -> Void = { _ in }

    private(set) var isRunning = false
    private var task: Task<(ResearchReport.Parsed?, String, String?), Never>?
    private var stopped = false
    /// True while the browser agent is doing the research, so Stop can reach it.
    private var usingBrowser = false

    struct Outcome: Sendable {
        var spoken = ""
        var report: URL?
        var problem: String?
        var cancelled = false
    }

    /// Runs one question to the end. nil when another run is going.
    /// `restricted` carries the command-line policy (control off): the browser fallback is refused.
    func start(question rawQuestion: String, depth requested: ResearchDepth, speak: Bool,
               restricted: Bool = CLIAccess.turnRestricted) async -> Outcome? {
        // Settings › Features › Research: Deep makes every report deep.
        let depth: ResearchDepth = requested == .quick ? FeatureSettings.researchDepth() : requested
        guard !isRunning else { return nil }
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return finish(Outcome(spoken: "What should I look into?", problem: "no question"), question: question, depth: depth, speak: speak, engine: nil) }
        isRunning = true
        stopped = false
        showCard(question: question, task: depth == .deep ? "Researching in depth" : "Researching")
        let work = Task { await self.research(question: question, depth: depth, restricted: restricted) }
        task = work
        let (parsed, engine, problem) = await work.value
        task = nil
        isRunning = false
        if stopped || Task.isCancelled { return finish(Outcome(spoken: "Stopped.", cancelled: true), question: question, depth: depth, speak: speak, engine: nil) }
        guard let parsed else {
            let raw = problem ?? "failed"
            VoiceLog.logContent("error", raw, prefix: "research provider error ")
            let spoken = VoiceTurnController.spokenError(ClaudeCLIProvider.ProviderError.failed(raw))
            return finish(Outcome(spoken: spoken, problem: raw), question: question, depth: depth, speak: speak, engine: nil)
        }
        let report = save(question: question, depth: depth, parsed: parsed, engine: engine)
        var spoken = parsed.summary.isEmpty ? "Done. The report is saved." : parsed.summary
        if report == nil { spoken += " I couldn't save the report." }
        record(question: question, depth: depth, parsed: parsed, engine: engine, report: report)
        return finish(Outcome(spoken: spoken, report: report), question: question, depth: depth, speak: speak, engine: engine)
    }

    func stop() {
        guard isRunning else { return }
        stopped = true
        task?.cancel()
        // The browser fallback is its own task, so cancelling the research task never reaches it.
        if usingBrowser { BrowserAgentRunner.shared.stop() }
    }

    // MARK: The run

    private func research(question: String, depth: ResearchDepth, restricted: Bool) async -> (ResearchReport.Parsed?, String, String?) {
        let router = RouterSettings.shared
        router.refresh()
        if AIConnections.shared.signedIn.isEmpty { await AIConnections.shared.checkAllSignIns() }
        let signedIn = AIConnections.shared.signedIn
        let installed = Set(router.installed.keys.filter { engine in
            guard let provider = AIProvider.allCases.first(where: { $0.routerEngine == engine }) else { return true }
            return signedIn[provider] != false
        })
        let order = ResearchReport.engineOrder(installed: installed, preferred: router.decide(.research).engine)
        let prompt = ResearchReport.prompt(question: question, depth: depth, persona: ZeusPersona.instructions)
        var lastError: String?
        for engine in order {
            guard let path = router.installed[engine], let arguments = ResearchReport.arguments(engine: engine, prompt: prompt, depth: depth) else { continue }
            do {
                let raw = try await BrowserAgentRunner.oneShot(path: path, arguments: arguments, timeout: depth.timeout)
                return (ResearchReport.parse(raw), engine.title, nil)
            } catch {
                if Task.isCancelled || stopped { return (nil, engine.title, nil) }
                lastError = (error as? BridgeError)?.message ?? error.localizedDescription
                VoiceLog.logContent("error", lastError ?? "?", prefix: "research \(engine.title) failed, trying next; detail ")
            }
        }
        // No engine with a web tool: the browser agent searches and reads the top results in Chrome.
        let fallback = await browserFallback(question, restricted: restricted)
        if let answer = fallback.answer {
            return (ResearchReport.parse(answer), "Browser agent", nil)
        }
        // The browser explanation is kept next to the engine error, never hidden behind it.
        let engineProblem = lastError.map { "Research failed: \($0.prefix(120))" }
        let browserProblem = fallback.problem.map { "the browser agent can't help: \($0)" }
        if let engineProblem { return (nil, "", [engineProblem, browserProblem].compactMap { $0 }.joined(separator: "; ")) }
        return (nil, "", browserProblem.map { "I need Claude or Gemini signed in to research the web, and \($0)" }
            ?? "I need Claude or Gemini signed in to research the web, or Chrome connected for the browser agent.")
    }

    /// Why the browser agent is refused while command-line control is off.
    static let restrictedBrowserRefusal = "command-line control is off, so I won't drive the browser (turn on 'Allow command-line control' in Settings ▸ Privacy)"

    /// The browser agent's answer, or why it couldn't give one (nil problem when it was busy or stopped).
    /// A restricted (command-line, control off) run is refused here, at the point the browser would start.
    private func browserFallback(_ question: String, restricted: Bool) async -> (answer: String?, problem: String?) {
        if restricted { return (nil, Self.restrictedBrowserRefusal) }
        let runner = BrowserAgentRunner.shared
        guard !runner.isRunning, !stopped else { return (nil, nil) }
        let goal = "Research this on the web: \(question). Search for it, open the top results one by one and read them with extract, "
            + "then finish with a short answer of one or two sentences and the page addresses you used."
        usingBrowser = true
        defer { usingBrowser = false }
        switch await runner.start(goal: goal, speak: false) {
        case .done(let answer)? where !answer.isEmpty: return (answer, nil)
        case .failed(let why)?: return (nil, why)
        default: return (nil, nil)
        }
    }

    // MARK: Saving and showing

    private func save(question: String, depth: ResearchDepth, parsed: ResearchReport.Parsed, engine: String) -> URL? {
        let now = Date()
        let connection = TodoController.shared.connection
        let name = ResearchReport.fileName(title: ResearchReport.title(for: question), date: now)
        let url = ResearchReport.destination(fileName: name, connection: connection)
        let text = ResearchReport.markdown(question: question, depth: depth, parsed: parsed, engine: engine, date: now)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            return url
        } catch {
            VoiceLog.logContent("error", error.localizedDescription, prefix: "research save failed: ")
            return nil
        }
    }

    private func record(question: String, depth: ResearchDepth, parsed: ResearchReport.Parsed, engine: String, report: URL?) {
        var answer = parsed.summary.isEmpty ? "" : "**\(parsed.summary)**\n\n"
        answer += parsed.body
        if let report { answer += "\n\nSaved to \(ProjectIndex.tilde(report.path))" }
        ChatModel.shared.recordExchange(user: "Research (\(depth.rawValue)): \(question)", assistant: answer, engine: engine)
    }

    // MARK: Card and voice

    private func showCard(question: String, task: String) {
        guard let notch else { return }
        let project = question.count > 52 ? String(question.prefix(51)) + "…" : question
        notch.model.stopHandlers[Self.sessionID] = { ResearchRunner.shared.stop() }
        notch.startSession(id: Self.sessionID, agent: "Research", project: project, task: task + "…")
    }

    private func finish(_ outcome: Outcome, question: String, depth: ResearchDepth, speak: Bool, engine: String?) -> Outcome {
        if let notch, notch.model.sessions.contains(where: { $0.id == Self.sessionID }) {
            let ok = outcome.problem == nil && !outcome.cancelled
            notch.update(sessionID: Self.sessionID, status: ok ? .done : .idle, task: ok ? "Report saved" : (outcome.cancelled ? "Stopped" : "Couldn't finish"))
            notch.model.stopHandlers[Self.sessionID] = nil
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(8))
                guard !ResearchRunner.shared.isRunning else { return }
                notch?.removeSession(id: Self.sessionID)
            }
        }
        AvatarStatus.shared.flash(outcome.problem == nil && !outcome.cancelled ? .done : .error, for: 2)
        if speak, !outcome.spoken.isEmpty { say(outcome.spoken) }
        return outcome
    }
}
