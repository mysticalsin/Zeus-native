import SwiftUI
import ZeusCore

/// Chat tab as the agent hub. Running Claude Code, Codex, Gemini and Cursor sessions on the left,
/// the selected one on the right with a reply field that types into its terminal (after an approval
/// card); "New chat" picks an agent, a project folder and an instruction and starts it in a terminal.
/// ZEUS's own chat keeps its transcript, History and floating window.
struct ChatPage: View {
    let chat: ChatModel
    @Bindable var hub: AgentHub = .shared
    @AppStorage("chat.page.showHistory") private var showHistory = false

    private var sessions: [NotchModel.Session] { hub.sessions }
    private var selected: NotchModel.Session? { sessions.first { $0.id == hub.selectedSession } }
    private var zeusChatHasContent: Bool { !chat.current.messages.isEmpty || chat.isSendingHere }
    private var isEmpty: Bool { !showHistory && !hub.creating && sessions.isEmpty && !zeusChatHasContent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                capsule("New chat", symbol: "plus", active: hub.creating) {
                    showHistory = false
                    if hub.creating { hub.creating = false } else { hub.beginNewChat() }
                }
                capsule("History", count: chat.conversations.count, symbol: "clock", active: showHistory) {
                    hub.creating = false
                    withAnimation(TopBarStyle.pageSpring) { showHistory.toggle() }
                }
                Spacer(minLength: 0)
                if chat.isSending {
                    Text("Writing…").font(TopBarStyle.label(11, .medium)).foregroundStyle(Theme.cloudQuiet).transition(.opacity)
                }
            }
            if hub.creating {
                NewChatForm(hub: hub)
            } else if showHistory {
                Tile(padding: 14) {
                    history.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else if isEmpty {
                GlanceSplitEmpty(
                    leftTitle: "Chat",
                    left: AnyView(AvatarView(state: .idle, size: 96).frame(maxWidth: .infinity, maxHeight: .infinity)),
                    title: "Nothing running",
                    detail: "Start a chat with your favorite agent",
                    primary: "New chat",
                    primaryAction: { hub.beginNewChat() }
                )
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Tile(padding: 8) { agentList }.frame(width: 270)
                    Tile(padding: 14) {
                        detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    // MARK: Agents

    private var agentList: some View {
        PageScroll(.vertical) {
            VStack(spacing: 3) {
                if zeusChatHasContent {
                    listRow(title: "Zeus", subtitle: chat.current.displayTitle, color: Theme.accent, picked: selected == nil) { hub.selectedSession = nil }
                }
                ForEach(sessions) { session in
                    listRow(agent: session.agent, subtitle: MeetingState.hideDetails ? session.status.label : "\(session.project) · \(session.status.label)",
                            color: session.status.color, picked: selected?.id == session.id) { hub.selectedSession = session.id }
                }
            }
        }
    }

    private func listRow(title: String? = nil, agent: String? = nil, subtitle: String, color: Color, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    if let agent {
                        HStack(spacing: 6) {
                            EngineBrandLogo(agentLabel: agent, size: 14).accessibilityHidden(true)
                            Text(agent).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                        }
                    } else if let title {
                        Text(title).font(TopBarStyle.label(12, .semibold)).foregroundStyle(Theme.cloudPrimary).lineLimit(1)
                    }
                    Text(subtitle).font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(Color.white.opacity(picked ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder
    private var detail: some View {
        if let session = selected {
            AgentReplyPane(hub: hub, session: session)
        } else if zeusChatHasContent {
            ChatTranscriptView(chat: chat, compact: true)
                .contentShape(Rectangle())
                .onTapGesture { chat.openWindow() }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick an agent").font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary)
                Text("Reply to a running session from here, or start a new chat.").font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudQuiet)
            }
        }
    }

    private func capsule(_ title: String, count: Int? = nil, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(TopBarStyle.label(12, .semibold))
                if let count, count > 0 {
                    Text("\(count)").font(TopBarStyle.label(11, .semibold).monospacedDigit()).foregroundStyle(Theme.cloudQuiet)
                }
            }
            .foregroundStyle(active ? Theme.cloudPrimary : Theme.cloudSecondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color.white.opacity(active ? 0.14 : 0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var history: some View {
        Group {
            if chat.conversations.isEmpty {
                Text("No chats yet.").font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudQuiet)
            } else {
                PageScroll(.vertical) {
                    LazyVStack(spacing: 4) {
                        ForEach(chat.conversations) { conversation in row(conversation) }
                    }
                }
            }
        }
    }

    private func row(_ conversation: ChatConversation) -> some View {
        let selected = conversation.id == chat.currentID
        return Button {
            chat.select(conversation.id)
            hub.selectedSession = nil
            withAnimation(TopBarStyle.pageSpring) { showHistory = false }
        } label: {
            HStack(spacing: 8) {
                Text(conversation.displayTitle).font(TopBarStyle.label(12, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.cloudPrimary : Theme.cloudSecondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(conversation.updatedAt, format: .relative(presentation: .named, unitsStyle: .narrow))
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.white.opacity(selected ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

extension NotchModel.Status {
    /// The word on a hub row.
    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Running"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Failed"
        case .stalled: "Stalled"
        }
    }
}

/// The selected session: what it is doing, a reply field and the way to its terminal.
private struct AgentReplyPane: View {
    @Bindable var hub: AgentHub
    let session: NotchModel.Session

    var body: some View {
        let canType = hub.canReply(to: session.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                EngineBrandLogo(agentLabel: session.agent, size: 16).accessibilityHidden(true)
                Text(session.agent).font(TopBarStyle.label(13, .semibold)).foregroundStyle(Theme.cloudPrimary)
                if !MeetingState.hideDetails {
                    Text(session.project).font(TopBarStyle.label(11.5)).foregroundStyle(Theme.cloudQuiet)
                }
                Spacer(minLength: 0)
                Text(session.status.label).font(TopBarStyle.label(11, .semibold)).foregroundStyle(session.status.color)
            }
            Text(MeetingState.hideDetails ? "Details hidden" : (session.reason ?? session.task))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.cloudSecondary).lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                NotchTextField(text: $hub.replyDraft, placeholder: canType ? "Reply to \(session.agent)" : "Reply in the terminal", onSubmit: send)
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .disabled(!canType)
                    .opacity(canType ? 1 : 0.5)
                if AgentTerminals.shared.canJump(to: session.id) {
                    CardButton(title: "Open", tint: Theme.cloudSecondary, filled: false) { hub.openTerminal(session.id) }
                }
                CardButton(title: hub.sending ? "Sending…" : "Send", tint: Theme.accent, filled: true, action: send)
                    .opacity(canType && !hub.replyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 0.4)
                    .disabled(!canType || hub.sending)
            }
            Text(hub.receipt ?? (canType ? "A card asks before anything is typed into the terminal." : "Replies can be typed into Terminal and iTerm2 sessions."))
                .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
        }
    }

    private func send() { Task { await hub.sendReply(session: session) } }
}

/// New chat: agent, project folder, instruction, Start.
private struct NewChatForm: View {
    @Bindable var hub: AgentHub

    var body: some View {
        Tile(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(hub.offeredTools, id: \.self) { tool in
                        Button { hub.newTool = tool } label: {
                            HStack(spacing: 6) {
                                EngineBrandLogo(agentLabel: tool.title, size: 14,
                                                tint: hub.newTool == tool ? Theme.storm : Theme.cloudSecondary)
                                    .accessibilityHidden(true)
                                Text(tool.title).font(TopBarStyle.label(12, .semibold))
                            }
                                .foregroundStyle(hub.newTool == tool ? Theme.storm : Theme.cloudSecondary)
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(Capsule().fill(hub.newTool == tool ? Theme.accent : Color.white.opacity(0.09)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(tool.title)
                        .accessibilityAddTraits(hub.newTool == tool ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(hub.projects, id: \.path) { project in
                            Button(project.name) { hub.newDirectory = project.path }
                        }
                        if hub.projects.isEmpty { Text("No projects found yet") }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder").font(.system(size: 11, weight: .semibold))
                            Text(folderTitle).font(TopBarStyle.label(12, .semibold)).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Theme.cloudPrimary)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.09)))
                    }
                    .menuStyle(.button).buttonStyle(.plain).fixedSize()
                }
                HStack(spacing: 8) {
                    NotchTextField(text: $hub.newInstruction, placeholder: hub.offeredTools.isEmpty ? "Choose an agent in Settings first" : "What should \(hub.newTool.title) do?", onSubmit: start)
                        .padding(.horizontal, 10).frame(height: 32)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    CardButton(title: hub.launching ? "Starting…" : "Start", tint: Theme.accent, filled: true, action: start)
                        .opacity(hub.canLaunch ? 1 : 0.4)
                        .disabled(!hub.canLaunch)
                }
                Text(hub.offeredTools.isEmpty ? "Choose an agent in Settings → Integrations to start a new chat."
                     : hub.launchMessage ?? "Opens \(hub.newTool.title) in your terminal. It shows up here and in the notch once it starts.")
                    .font(TopBarStyle.label(10.5)).foregroundStyle(Theme.cloudQuiet).lineLimit(1)
            }
        }
    }

    private var folderTitle: String {
        let name = URL(fileURLWithPath: hub.newDirectory).lastPathComponent
        return name.isEmpty ? "Choose a folder" : name
    }

    private func start() { Task { await hub.launch() } }
}
