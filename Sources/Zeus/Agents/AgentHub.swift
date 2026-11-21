import AppKit
import Observation
import ZeusCore

/// The Chat tab as the agent hub: replies to running sessions and the New chat flow.
@MainActor
@Observable
final class AgentHub {
    static let shared = AgentHub()

    weak var notch: NotchController?
    /// Snapshots and previews show these instead of the live sessions.
    @ObservationIgnored var sessionsOverride: [NotchModel.Session]?
    var sessions: [NotchModel.Session] { sessionsOverride ?? notch?.model.sessions ?? [] }

    // MARK: Reply

    var selectedSession: String? {
        didSet {
            guard !syncingReply, oldValue != selectedSession else { return }
            let wasAwaiting = replyGate.state.status == .awaitingDecision
            let step = replyGate.bind(selectedSession)
            publish(step, wasAwaiting: wasAwaiting)
        }
    }
    var replyDraft = "" {
        didSet {
            guard !syncingReply, oldValue != replyDraft else { return }
            let session = selectedSession ?? ""
            let wasAwaiting = replyGate.state.status == .awaitingDecision
            let step = replyGate.perform(
                .textChanged,
                sessionID: session,
                field: replyDraft,
                destinationCanTakeText: canReply(to: session),
                trusted: replyIsTrusted(session))
            publish(step, wasAwaiting: wasAwaiting)
            if replyDraft != replyGate.state.draft {
                syncingReply = true
                replyDraft = replyGate.state.draft
                syncingReply = false
            }
        }
    }
    private(set) var sending = false
    /// What the last send did, shown under the field.
    private(set) var receipt: String?
    /// Inline approval for the selected row. Trust does not set this by itself.
    var replyNeedsApproval: Bool { replyGate.state.status == .awaitingDecision }
    var replyPhase: HubReplyStatus { replyGate.state.status }
    /// The app and tty the pending reply will type into. Nil until that reply asks.
    var replyTarget: HubReplyTarget? { replyGate.state.target }

    /// The injected steps of the reply path. Tests and previews replace the runner.
    /// The bundled `send` is not called: its approval closure refuses, so it cannot type.
    @ObservationIgnored var sender: AgentReplySender?
    /// Tests supply the foreground process name. Production reads it with AppleScript.
    @ObservationIgnored var foregroundProbe: ((TerminalInfo) -> String?)?
    @ObservationIgnored private var syncingReply = false
    @ObservationIgnored private var replyGate = HubReplyDispatch()
    @ObservationIgnored private var replyTimeout: Task<Void, Never>?
    @ObservationIgnored private var replyEpoch = 0

    func canReply(to session: String) -> Bool {
        AgentReply.supports(AgentTerminals.shared.info(for: session))
    }

    /// Asks inline. Nothing is typed from this call.
    func sendReply(session: NotchModel.Session) async {
        guard session.id == selectedSession, !session.id.isEmpty else { return }
        guard replyGate.state.status != .sending else { return }
        let wasAwaiting = replyGate.state.status == .awaitingDecision
        let target = HubReplyTarget.make(info: AgentTerminals.shared.info(for: session.id), agent: session.agent)
        let step = replyGate.perform(
            .send,
            sessionID: session.id,
            field: replyDraft,
            destinationCanTakeText: canReply(to: session.id),
            trusted: replyIsTrusted(session.id),
            target: target)
        publish(step, wasAwaiting: wasAwaiting)
    }

    /// Types the approved line. A missing approval, a bad destination, or an unsafe line types nothing.
    func approveReply() async {
        guard let session = selectedSession, !session.isEmpty else { return }
        guard replyGate.state.status == .awaitingDecision else { return }
        let info = (sender ?? liveSender).terminal(session)
        let fresh = HubReplyTarget.make(info: info, agent: "")
        if let shown = replyTarget {
            _ = HubReplyTargetGate.refusal(shown: shown, current: fresh)
        }
        let expected = replyTarget?.expectedCLI ?? []
        let verdict = foregroundVerdict(info: info, expected: expected)
        let step = replyGate.perform(
            .approved,
            sessionID: session,
            field: replyDraft,
            destinationCanTakeText: canReply(to: session),
            trusted: replyIsTrusted(session),
            target: fresh,
            foreground: verdict)
        publish(step, wasAwaiting: true)
        guard let line = step.typedLine, step.sessionID == session else { return }
        let typed = await typeApprovedLine(line, sessionID: session)
        guard selectedSession == session else { return }
        let done = replyGate.finished(sessionID: session, typed: typed)
        publish(done, wasAwaiting: false)
    }

    func denyReply() {
        guard let session = selectedSession, !session.isEmpty else { return }
        let step = replyGate.perform(
            .denied,
            sessionID: session,
            field: replyDraft,
            destinationCanTakeText: canReply(to: session),
            trusted: replyIsTrusted(session))
        publish(step, wasAwaiting: true)
    }

    func cancelReply() {
        guard let session = selectedSession, !session.isEmpty else { return }
        let step = replyGate.cancel(sessionID: session)
        publish(step, wasAwaiting: true)
    }

    func timeoutReply() {
        guard let session = selectedSession, !session.isEmpty else { return }
        let step = replyGate.perform(
            .timedOut,
            sessionID: session,
            field: replyDraft,
            destinationCanTakeText: canReply(to: session),
            trusted: replyIsTrusted(session))
        publish(step, wasAwaiting: true)
    }

    func openTerminal(_ session: String) { AgentTerminals.shared.jump(to: session) }

    private func publish(_ step: HubReplyDispatch.Step, wasAwaiting: Bool) {
        syncingReply = true
        replyDraft = step.state.draft
        receipt = step.state.receipt?.rawValue
        sending = step.state.status == .sending
        syncingReply = false
        let awaiting = step.state.status == .awaitingDecision
        if awaiting, !wasAwaiting {
            armReplyTimeout()
        } else if !awaiting {
            replyEpoch += 1
            replyTimeout?.cancel()
            replyTimeout = nil
        }
    }

    /// The existing reply wait. It denies. It is not the chime window and not the stall limit.
    private func armReplyTimeout() {
        replyTimeout?.cancel()
        replyEpoch += 1
        let epoch = replyEpoch
        let session = selectedSession
        replyTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, epoch == self.replyEpoch, self.selectedSession == session else { return }
            guard self.replyGate.state.status == .awaitingDecision else { return }
            self.timeoutReply()
        }
    }

    private func replyIsTrusted(_ session: String) -> Bool {
        TrustedChatStore.shared.chats.isTrusted(session)
    }

    /// Builds a script only after the gate has released a line, then runs it only if the guard agrees.
    private func typeApprovedLine(_ line: String, sessionID: String) async -> Bool {
        guard sessionID == selectedSession, !sessionID.isEmpty else { return false }
        guard HubReplyTyping.canType(line) else { return false }
        let typer = sender ?? liveSender
        guard let info = typer.terminal(sessionID) else { return false }
        let expected = replyGate.state.target?.expectedCLI ?? []
        if sender == nil {
            let name = foregroundName(info)
            let path = name?.contains("/") == true ? name : nil
            let verdict = HubReplyForeground.verdict(
                name: name,
                expected: expected,
                executablePath: path,
                allowedPaths: allowedAgentPaths(expected))
            guard verdict == .agent else { return false }
        }
        guard let script = AgentReply.script(for: info, text: line, expectedCLI: expected) else { return false }
        guard HubReplyScriptGuard.mayRun(script: script, line: line, approved: true) else { return false }
        guard sessionID == selectedSession else { return false }
        if let sender {
            return await sender.run(script)
        }
        return await Self.runGuardedScript(script)
    }

    private var liveSender: AgentReplySender {
        AgentReplySender(
            // Safe: the terminal lookup reads main-actor state, and this closure runs on the main actor.
            terminal: { session in MainActor.assumeIsolated { AgentTerminals.shared.info(for: session) } },
            approve: { _, _ in false },
            run: { script in await Self.runGuardedScript(script) })
    }

    /// Production asks the terminal what is in the foreground. An injected sender does not.
    private func foregroundVerdict(info: TerminalInfo?, expected: Set<String>) -> HubReplyForeground.Verdict? {
        let name: String?
        if sender != nil {
            name = info.flatMap { foregroundProbe?($0) }
        } else {
            name = info.flatMap(foregroundName)
        }
        guard sender == nil || foregroundProbe != nil else { return nil }
        return HubReplyForeground.verdict(name: name, expected: expected)
    }

    /// Paths of the expected CLIs, resolved later against the process path when the terminal returns one.
    /// A bare name from `processes` or `jobName` has no path to compare. See `HubReplyForeground`.
    private func allowedAgentPaths(_ expected: Set<String>) -> Set<String> {
        Set(CLILocator.tools.compactMap { tool in
            expected.contains(tool.name) ? CLILocator.locate(tool) : nil
        })
    }

    /// Terminal's `processes` or iTerm's `jobName`. The automation permission is the one the app already has.
    private func foregroundName(_ info: TerminalInfo) -> String? {
        guard let bundle = info.targetBundleID, let tty = info.tty else { return nil }
        let script = HubReplyForeground.queryScript(bundleID: bundle, tty: tty)
        guard !script.isEmpty else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let text = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func runGuardedScript(_ script: String) async -> Bool {
        await MainActor.run {
            var error: NSDictionary?
            return NSAppleScript(source: script)?.executeAndReturnError(&error).booleanValue == true
        }
    }

    // MARK: New chat

    var creating = false
    var newTool: CodingTool = .claude
    var newDirectory = ""
    var newInstruction = ""
    private(set) var launching = false
    private(set) var launchMessage: String?

    /// Agents offered in New chat, from Settings > Integrations and the CLIs on this Mac.
    var offeredTools: [CodingTool] {
        let connections = AIConnections.shared
        let installed = Set([CodingTool.gemini, .cursorAgent].filter { tool in
            CLILocator.tools.first(where: { $0.name == tool.binary }).flatMap(CLILocator.locate) != nil
        })
        return NewChatAgents.offered(claude: connections.offers(.claudeCode), codex: connections.offers(.codex),
                                     gemini: connections.offers(.gemini), cursor: connections.offers(.cursor), installed: installed)
    }

    var projects: [ProjectEntry] { Array(ProjectScanner.shared.entries.sorted { $0.name.lowercased() < $1.name.lowercased() }.prefix(60)) }

    func beginNewChat() {
        let offered = offeredTools
        newTool = NewChatAgents.defaultTool(label: SettingsStore.shared.string("general.defaultAgent"), offered: offered)
        if newDirectory.isEmpty { newDirectory = projects.first?.path ?? FileManager.default.homeDirectoryForCurrentUser.path }
        newInstruction = ""
        launchMessage = nil
        creating = true
    }

    var request: NewChatRequest { NewChatRequest(tool: newTool, directory: newDirectory, instruction: newInstruction) }
    var canLaunch: Bool { request.isValid && offeredTools.contains(newTool) && !launching }

    func launch() async {
        guard canLaunch, let command = request.command else { return }
        launching = true
        defer { launching = false }
        let result = await CodeActions.shared.perform(command, speak: false)
        launchMessage = result.message
        if result.ok {
            newInstruction = ""
            creating = false
        }
    }
}
