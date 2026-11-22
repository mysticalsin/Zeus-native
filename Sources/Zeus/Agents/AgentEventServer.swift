import AppKit
import ZeusCore

/// Receives agent hook events from `zeus-hook` and turns them into notch sessions and approvals.
@MainActor
final class AgentEventServer {
    private let notch: NotchController
    private var server: UnixSocketServer?
    private var collapseTask: Task<Void, Never>?
    /// Last answer per session, for agents that report it separately from stop.
    private var lastResponse: [String: String] = [:]
    private var codexWatcher: CodexSessionWatcher?
    /// Hub sessions driven by hook lines. The notch rows follow this book.
    private var hubBook = HubHookBook()
    /// The one sound decision from the latest finish. This server does not play a second sound.
    private(set) var lastFinishDecisions: [HubSoundDecision] = []
    /// Down until the socket binds. A failure stays the connection-error sentence, with no path in it.
    private(set) var lastError: String? = HubScreen.connectionError.sentence

    var hubScreen: HubScreen { hubBook.screen }
    /// Answers `zeus` CLI commands, which share this socket with hook events. The peer context says
    /// whether the sender is this app's own signed `zeus` command.
    var commandHandler: (@MainActor (Data, PeerContext) async -> Data?)?

    init(notch: NotchController) {
        self.notch = notch
    }

    func start() {
        if server != nil { return }
        codexWatcher?.stop()
        let watcher = CodexSessionWatcher { [weak self] event in
            Task { @MainActor in _ = await self?.process(event) }
        }
        watcher.start()
        codexWatcher = watcher
        let path = ZeusPaths.socket.path
        // The listener admits the same user before a line is read. A path that cannot bind
        // becomes a connection error, and the error text does not include the path.
        guard HubHookGate.acceptsSocketPath(path, expected: path) else {
            noteSocketFailed()
            return
        }
        hubBook.beginOpening()
        let server = UnixSocketServer(path: path, peerPolicy: .sameUser, contextHandler: { [weak self] line, peer, reply in
            // With command-line control on, the sender's signature is read here, off the main thread,
            // so the main actor only reads the remembered answer.
            if CLIAccess.enabled, ZeusCommand.isCommand(line) { _ = peer.verifiedApp() }
            Task { @MainActor in
                guard let self else { return reply(nil) }
                reply(await self.handle(line, peer: peer))
            }
        })
        do {
            try server.start()
            self.server = server
            lastError = nil
            hubBook.open()
        } catch {
            noteSocketFailed()
        }
    }

    func stop() {
        server?.stop()
        server = nil
        hubBook.fail()
        lastError = HubScreen.connectionError.sentence
    }

    private func noteSocketFailed() {
        server?.stop()
        server = nil
        hubBook.fail()
        lastError = HubScreen.connectionError.sentence
        NSLog("[ZEUS] agent socket failed")
    }

    /// Returns the reply line for decision events, nil otherwise.
    private func handle(_ line: Data, peer: PeerContext) async -> Data? {
        if ZeusCommand.isCommand(line) {
            guard let commandHandler else {
                let probe = try? JSONDecoder().decode(ZeusCommand.self, from: line)
                let id = probe?.id ?? "unknown"
                return try? JSONEncoder().encode(ZeusCommandReply(id: id, ok: false, text: "Zeus is still starting up."))
            }
            return await commandHandler(line, peer)
        }
        // The listener already refused a peer that is not this user. The line is bounded here,
        // and a rejection is returned without the payload.
        guard case .success(let message) = HubHookGate.inspect(line: line, peer: .allow) else { return nil }
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: line) else { return nil }
        return await accept(event, message: message)
    }

    /// One agent event from a hook or a log watcher. Returns the reply for decision events.
    func process(_ event: HookEvent) async -> Data? {
        guard let line = try? JSONEncoder().encode(event),
              case .success(let message) = HubHookGate.inspect(line: line, peer: .allow) else { return nil }
        return await accept(event, message: message)
    }

    private func accept(_ event: HookEvent, message: HubHookMessage) async -> Data? {
        var message = message
        let sessionID = message.sessionID
        let agent = Self.agentName(event.source)
        let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No project"
        FlightRecorder.shared.record("agent", event.event, "\(agent) \(project) session \(sessionID.prefix(8))\(event.tool.map { " tool \($0)" } ?? "")")
        AgentTerminals.shared.remember(event.terminal, for: sessionID)
        let risk = HookClientInput.effectiveRisk(claimed: event.risk, tool: event.tool, input: event.input)
        if event.event == "PermissionRequest",
           HubHookFamily.canAsk(event.source),
           !HubHookFamily.isQuestion(event: event.event, tool: event.tool),
           event.input?["command"]?.stringValue.flatMap(HandsBlocklist.reason) == nil,
           TrustedChatStore.shared.autoApproves(session: sessionID, tool: event.tool, input: event.input, risk: risk) {
            message.autoApproves = true
        }
        let before = hubBook.sessions[sessionID] ?? HubSessionState()
        let step = hubBook.apply(
            message,
            now: Date(),
            systemFinishSound: AgentSettings.shared.completionSound
        )
        if event.event == "PostToolUse", event.tool == "AskUserQuestion" {
            QuestionAnswers.shared.toolResult(session: sessionID, text: event.detail)
        }
        if event.event == "AgentResponse", let text = event.detail {
            lastResponse[sessionID] = text
        }
        if event.event == "PermissionRequest" {
            return await permission(event, message: message, step: step, before: before, agent: agent, project: project, risk: risk)
        }
        if event.event == "Stop" {
            if step.soundDecisions.count == 1 { lastFinishDecisions = step.soundDecisions }
            let detail = event.detail ?? lastResponse[sessionID]
            let startedAt = notch.model.sessions.first { $0.id == sessionID }?.startedAt
            showCompletion(AgentCompletion(sessionID: sessionID, agent: agent, project: project, summary: detail, startedAt: startedAt))
        }
        if event.event == "UserPromptSubmit" { peekBriefly() }
        let task = taskLine(event, state: step.state)
        sync(sessionID, agent: agent, project: project, task: task, before: before, after: step.state)
        if event.event == "Stop" || event.event == "SessionEnd" { lastResponse[sessionID] = nil }
        if event.event == "SessionEnd" {
            AgentTerminals.shared.forget(sessionID)
            TrustedChatStore.shared.revoke(session: sessionID)
        }
        if event.event == "Notification", QuestionAnswers.shared.waitingForInput(session: sessionID) {
            notch.upsertSession(id: sessionID, agent: agent, project: project, task: "answer in the terminal", status: .needsYou)
            peekBriefly(seconds: 5)
        }
        return nil
    }

    private func permission(
        _ event: HookEvent,
        message: HubHookMessage,
        step: HubHookStep,
        before: HubSessionState,
        agent: String,
        project: String,
        risk: HookEvent.Risk
    ) async -> Data? {
        let sessionID = message.sessionID
        if let command = event.input?["command"]?.stringValue, let reason = HandsBlocklist.reason(command) {
            HandsCommandLogger.append(command: command, verdict: "blocked", outcome: reason)
            sync(sessionID, agent: agent, project: project, task: reason, before: before, after: step.state)
            return try? JSONEncoder().encode(HookDecision(id: event.id, decision: .deny, reason: reason))
        }
        if message.autoApproves {
            let task = Self.describe(tool: event.tool ?? "Tool", input: event.input)
            sync(sessionID, agent: agent, project: project, task: task, before: before, after: step.state)
            return try? JSONEncoder().encode(HookDecision(id: event.id, decision: .allow))
        }
        let task = taskLine(event, state: step.state)
        sync(sessionID, agent: agent, project: project, task: task, before: before, after: step.state)
        guard step.growsApprove else {
            guard event.needsDecision else { return nil }
            if HubHookFamily.isQuestion(event: event.event, tool: event.tool) {
                return try? JSONEncoder().encode(HookDecision(id: event.id, decision: .ask))
            }
            return try? JSONEncoder().encode(HookDecision(id: event.id, decision: .deny, reason: "Zeus can't approve this session."))
        }
        collapseTask?.cancel()
        let detail = ApprovalDetail.make(tool: event.tool, input: event.input, session: sessionID)
        var trust: (session: String, onTrust: @MainActor () -> Void)?
        if TrustedChats.canOffer(tool: event.tool, input: event.input, risk: risk) {
            let onTrust: @MainActor () -> Void = { TrustedChatStore.shared.trust(session: sessionID, agent: agent, project: project) }
            trust = (sessionID, onTrust)
        }
        let verdict = await notch.requestApproval(
            agent: agent,
            project: project,
            tool: Self.cardTitle(tool: event.tool),
            command: Self.command(tool: event.tool, input: event.input),
            risk: risk,
            timeout: .seconds(100),
            onTimeout: .ask,
            detail: detail,
            trust: trust
        )
        let resolved = hubBook.resolve(sessionID: sessionID, verdict: verdict, now: Date())
        sync(sessionID, agent: agent, project: project, task: task, before: step.state, after: resolved.state)
        peekBriefly()
        let decision: HookDecision
        if let detail, detail.answered, verdict == .allow {
            decision = QuestionAnswers.shared.decision(id: event.id, session: sessionID, input: detail.input, answers: detail.choices)
        } else {
            decision = HookDecision(id: event.id, decision: verdict,
                                    reason: verdict == .deny ? (detail?.denyMessage ?? "Denied in Zeus") : nil,
                                    updatedInput: verdict == .allow ? detail?.updatedInput : nil)
        }
        return try? JSONEncoder().encode(decision)
    }

    private func taskLine(_ event: HookEvent, state: HubSessionState) -> String {
        switch state.status {
        case .absent:
            return ""
        case .loading:
            return "ready"
        case .running:
            if event.event == "UserPromptSubmit" { return event.detail.map(Self.oneLine) ?? "working" }
            if let tool = event.tool { return Self.describe(tool: tool, input: event.input) }
            return "working"
        case .waitingForInput:
            return event.detail.map(Self.oneLine) ?? "waiting for input"
        case .needsApproval:
            return Self.describe(tool: event.tool ?? "Tool", input: event.input)
        case .done:
            let detail = event.detail ?? lastResponse[event.session ?? ""]
            return detail.map(Self.oneLine) ?? "finished"
        case .error(.quiet):
            return Self.quietReason(event.detail)
        case .error(.failed):
            return event.detail.map(Self.oneLine) ?? "The agent stopped with an error"
        }
    }

    private static func quietReason(_ detail: String?) -> String {
        guard let detail else { return "No activity for the limit" }
        let line = oneLine(detail)
        guard line.range(of: #"^No activity for [1-9][0-9]{0,3} min$"#, options: .regularExpression) != nil else {
            return "No activity for the limit"
        }
        return line
    }

    private func sync(
        _ id: String,
        agent: String,
        project: String,
        task: String,
        before: HubSessionState,
        after: HubSessionState
    ) {
        if after.status == .absent {
            if before.status != .absent { notch.removeSession(id: id) }
            return
        }
        let restart = after.clockGeneration > before.clockGeneration
        switch after.status {
        case .absent:
            break
        case .loading:
            notch.upsertSession(id: id, agent: agent, project: project, task: task, status: .idle)
        case .running:
            notch.upsertSession(id: id, agent: agent, project: project, task: task, status: .working, restartClock: restart)
        case .waitingForInput, .needsApproval:
            notch.upsertSession(id: id, agent: agent, project: project, task: task, status: .needsYou)
        case .done:
            notch.upsertSession(id: id, agent: agent, project: project, task: task, status: .done)
        case .error:
            if before.status != after.status {
                notch.failSession(id: id, agent: agent, project: project, reason: task)
            } else {
                notch.upsertSession(id: id, agent: agent, project: project, task: task, status: .failed)
            }
        }
    }

    /// The finished card. The sound decision was recorded once on the way in, so this does not play another.
    private func showCompletion(_ completion: AgentCompletion) {
        let settings = AgentSettings.shared
        let outcome = AgentQuietPolicy.outcome(
            for: .completion,
            fullScreen: FullScreenDetector.frontAppIsFullScreen(),
            quietEnabled: settings.quietInFullScreen,
            soundsEnabled: false
        )
        guard outcome.present else { return }
        guard settings.completionCards, notch.model.approval == nil else {
            // No card to show: a macOS banner (when Settings > Notifications allows it) says it finished.
            let alert = AgentAlert.finished(agent: completion.agent, project: completion.project,
                                            summary: completion.summary ?? "", session: completion.sessionID)
            Task { await SystemNotificationService.shared.deliverAgentAlert(alert) }
            return peekBriefly(seconds: 4)
        }
        notch.model.completion = completion
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "\(completion.agent) finished in \(completion.project)",
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        peekBriefly(seconds: 7)
    }

    /// Glance-style: show the peek, then fold back into the glowing notch. Quiet while a
    /// full-screen app is in front.
    private func peekBriefly(seconds: Double = 3.5) {
        let quiet = AgentQuietPolicy.outcome(for: .peek, fullScreen: FullScreenDetector.frontAppIsFullScreen(),
                                             quietEnabled: AgentSettings.shared.quietInFullScreen, soundsEnabled: false)
        guard quiet.present else { return }
        if notch.model.presentation == .closed { notch.show(.peek) }
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, notch.model.approval == nil, notch.model.presentation == .peek else { return }
            notch.model.completion = nil
            notch.show(.closed)
        }
    }

    static func agentName(_ source: HookEvent.Source) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor Agent"
        case .gemini: "Gemini CLI"
        }
    }

    /// The label at the top of an approval card.
    static func cardTitle(tool: String?) -> String {
        switch tool {
        case "ExitPlanMode": "Plan"
        case "AskUserQuestion": "Question"
        case nil: "Tool"
        case let tool?: tool
        }
    }

    static func oneLine(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 80 ? String(flat.prefix(79)) + "…" : flat
    }

    static func command(tool: String?, input: JSONValue?) -> String {
        if let command = input?["command"]?.stringValue { return oneLine(command) }
        if let path = input?["file_path"]?.stringValue { return "\(tool ?? "Edit") \(URL(fileURLWithPath: path).lastPathComponent)" }
        if let url = input?["url"]?.stringValue { return "\(tool ?? "Fetch") \(url)" }
        return tool ?? "tool call"
    }

    static func describe(tool: String, input: JSONValue?) -> String {
        switch tool {
        case "Bash": return input?["command"]?.stringValue.map(oneLine) ?? "running a command"
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            let file = input?["file_path"]?.stringValue.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "a file"
            return "\(tool.lowercased()) \(file)"
        case "Grep", "Glob": return "searching \(input?["pattern"]?.stringValue ?? "files")"
        case "WebFetch", "WebSearch": return "looking things up"
        default: return tool.hasPrefix("mcp__") ? tool.split(separator: "_").last.map(String.init) ?? tool : tool
        }
    }
}
