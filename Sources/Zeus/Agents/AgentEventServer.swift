import AppKit
import ZeusCore

/// Receives agent hook events from `zeus-hook` and turns them into notch sessions and approvals.
@MainActor
final class AgentEventServer {
    private let notch: NotchController
    private var server: UnixSocketServer?
    private var collapseTask: Task<Void, Never>?
    /// Last answer per session, for agents that report it separately from "stop" (Cursor).
    private var lastResponse: [String: String] = [:]
    private var codexWatcher: CodexSessionWatcher?
    private(set) var lastError: String?
    /// Answers `zeus` CLI commands, which share this socket with hook events.
    var commandHandler: (@MainActor (Data) async -> Data?)?

    init(notch: NotchController) {
        self.notch = notch
    }

    func start() {
        let server = UnixSocketServer(path: ZeusPaths.socket.path) { [weak self] line, reply in
            Task { @MainActor in
                guard let self else { return reply(nil) }
                reply(await self.handle(line))
            }
        }
        let watcher = CodexSessionWatcher { [weak self] event in
            Task { @MainActor in _ = await self?.process(event) }
        }
        watcher.start()
        codexWatcher = watcher
        do {
            try server.start()
            self.server = server
        } catch {
            lastError = "Could not open the agent socket: \(error)"
            NSLog("[ZEUS] %@", lastError ?? "")
        }
    }

    func stop() { server?.stop() }

    /// Returns the reply line for decision events, nil otherwise.
    private func handle(_ line: Data) async -> Data? {
        if ZeusCommand.isCommand(line) {
            guard let commandHandler else {
                let probe = try? JSONDecoder().decode(ZeusCommand.self, from: line)
                let id = probe?.id ?? "unknown"
                return try? JSONEncoder().encode(ZeusCommandReply(id: id, ok: false, text: "Zeus is still starting up."))
            }
            return await commandHandler(line)
        }
        guard let event = try? JSONDecoder().decode(HookEvent.self, from: line) else { return nil }
        return await process(event)
    }

    /// One agent event from a hook or a log watcher. Returns the reply for decision events.
    func process(_ event: HookEvent) async -> Data? {
        // The client's risk label is never trusted below what the app computes from the input.
        let risk = HookClientInput.effectiveRisk(claimed: event.risk, tool: event.tool, input: event.input)
        let sessionID = event.session ?? "unknown"
        let agent = Self.agentName(event.source)
        let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No project"
        FlightRecorder.shared.record("agent", event.event, "\(agent) \(project) session \(sessionID.prefix(8))\(event.tool.map { " tool \($0)" } ?? "")")
        AgentTerminals.shared.remember(event.terminal, for: sessionID)
        // Any event is a sign of life; it also lifts a stalled session.
        if event.event != "SessionEnd" { notch.touch(sessionID: sessionID) }

        switch event.event {
        case "SessionStart":
            notch.upsertSession(id: sessionID, agent: agent, project: project, task: "ready", status: .idle)

        case "UserPromptSubmit":
            let task = event.detail.map(Self.oneLine) ?? "working"
            notch.upsertSession(id: sessionID, agent: agent, project: project, task: task, status: .working, restartClock: true)
            peekBriefly()

        case "PreToolUse", "PostToolUse":
            if event.event == "PostToolUse", event.tool == "AskUserQuestion" {
                QuestionAnswers.shared.toolResult(session: sessionID, text: event.detail)
            }
            if let tool = event.tool {
                notch.upsertSession(id: sessionID, agent: agent, project: project,
                                    task: Self.describe(tool: tool, input: event.input), status: .working)
            }

        case "StopFailure":
            notch.failSession(id: sessionID, agent: agent, project: project,
                              reason: event.detail.map(Self.oneLine) ?? "The agent stopped with an error")

        case "PermissionRequest":
            if let command = event.input?["command"]?.stringValue, let reason = HandsBlocklist.reason(command) {
                HandsCommandLogger.append(command: command, verdict: "blocked", outcome: reason)
                notch.failSession(id: sessionID, agent: agent, project: project, reason: reason)
                let decision = HookDecision(id: event.id, decision: .deny, reason: reason)
                return try? JSONEncoder().encode(decision)
            }
            // A chat the person trusted ("Allow this whole chat") runs without a card, unless it is risky.
            if TrustedChatStore.shared.autoApproves(session: sessionID, tool: event.tool, input: event.input, risk: risk) {
                notch.upsertSession(id: sessionID, agent: agent, project: project,
                                    task: Self.describe(tool: event.tool ?? "Tool", input: event.input), status: .working)
                return try? JSONEncoder().encode(HookDecision(id: event.id, decision: .allow))
            }
            notch.upsertSession(id: sessionID, agent: agent, project: project,
                                task: Self.describe(tool: event.tool ?? "Tool", input: event.input), status: .needsYou)
            collapseTask?.cancel()
            let detail = ApprovalDetail.make(tool: event.tool, input: event.input, session: sessionID)
            var trust: (session: String, onTrust: @MainActor () -> Void)?
            if sessionID != "unknown", TrustedChats.canOffer(tool: event.tool, input: event.input, risk: risk) {
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
            notch.update(sessionID: sessionID, status: verdict == .deny ? .idle : .working)
            peekBriefly()
            let decision: HookDecision
            if let detail, detail.answered, verdict == .allow {
                // Answers go the way this Claude Code is known to honour (learned, see QuestionAnswers).
                decision = QuestionAnswers.shared.decision(id: event.id, session: sessionID, input: detail.input, answers: detail.choices)
            } else {
                decision = HookDecision(id: event.id, decision: verdict,
                                        reason: verdict == .deny ? (detail?.denyMessage ?? "Denied in Zeus") : nil,
                                        updatedInput: verdict == .allow ? detail?.updatedInput : nil)
            }
            return try? JSONEncoder().encode(decision)

        case "AgentResponse":
            if let text = event.detail { lastResponse[sessionID] = text }

        case "Stop":
            let detail = event.detail ?? lastResponse.removeValue(forKey: sessionID)
            let summary = detail.map(Self.oneLine) ?? "finished"
            let startedAt = notch.model.sessions.first { $0.id == sessionID }?.startedAt
            notch.upsertSession(id: sessionID, agent: agent, project: project, task: summary, status: .done)
            showCompletion(AgentCompletion(sessionID: sessionID, agent: agent, project: project, summary: detail, startedAt: startedAt))

        case "Notification":
            // Permission prompts arrive as PermissionRequest. A prompt right after ZEUS sent
            // answers means the terminal is still asking: answers switch to the message path.
            if QuestionAnswers.shared.waitingForInput(session: sessionID) {
                notch.upsertSession(id: sessionID, agent: agent, project: project, task: "answer in the terminal", status: .needsYou)
                peekBriefly(seconds: 5)
            }

        case "SessionEnd":
            notch.removeSession(id: sessionID)
            AgentTerminals.shared.forget(sessionID)
            TrustedChatStore.shared.revoke(session: sessionID)

        default:
            break
        }
        return nil
    }

    /// The finished card with a sound, unless a full-screen app asks for quiet.
    private func showCompletion(_ completion: AgentCompletion) {
        let settings = AgentSettings.shared
        let outcome = AgentQuietPolicy.outcome(for: .completion, fullScreen: FullScreenDetector.frontAppIsFullScreen(),
                                               quietEnabled: settings.quietInFullScreen, soundsEnabled: settings.completionSound)
        if outcome.sound { NSSound(named: NSSound.Name("Glass"))?.play() }
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
