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

    var selectedSession: String?
    var replyDraft = ""
    private(set) var sending = false
    /// What the last send did, shown under the field.
    private(set) var receipt: String?

    /// The injected steps of the reply path. Tests and previews replace them.
    @ObservationIgnored var sender: AgentReplySender?

    func canReply(to session: String) -> Bool {
        AgentReply.supports(AgentTerminals.shared.info(for: session))
    }

    /// Types the draft into the session's terminal after an approval card.
    func sendReply(session: NotchModel.Session) async {
        let text = replyDraft
        guard !sending else { return }
        sending = true
        receipt = nil
        defer { sending = false }
        let outcome = await (sender ?? liveSender).send(text, to: session.id, agent: session.agent)
        switch outcome {
        case .sent:
            replyDraft = ""
            receipt = "Sent to \(session.agent)'s terminal."
        case .empty: receipt = "Type something first."
        case .declined: receipt = "Not sent."
        case .unsupported:
            receipt = "This terminal can't take typed replies. Open it and reply there."
        case .failed:
            receipt = "I couldn't find that terminal tab. Open it and reply there."
        }
    }

    func openTerminal(_ session: String) { AgentTerminals.shared.jump(to: session) }

    private var liveSender: AgentReplySender {
        AgentReplySender(
            // Safe: AgentReplySender.send is @MainActor, so this closure only runs on the main thread.
            terminal: { session in MainActor.assumeIsolated { AgentTerminals.shared.info(for: session) } },
            approve: { [weak self] agent, text in await self?.approve(agent: agent, text: text) ?? false },
            run: { script in await Self.run(script) })
    }

    /// Typing into a terminal always asks first, on a notch card.
    private func approve(agent: String, text: String) async -> Bool {
        guard let notch else { return false }
        let verdict = await notch.requestApproval(agent: agent, project: "Reply", tool: "Terminal",
                                                  command: "type: \(text)", risk: .low, timeout: .seconds(30), onTimeout: .deny)
        return verdict == .allow
    }

    private static func run(_ script: String) async -> Bool {
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
