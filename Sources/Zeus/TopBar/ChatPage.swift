import Foundation
#if canImport(ZeusCore)
import ZeusCore
#endif

struct ChatBarState: Equatable {
    var transcript: HubTranscript
    var selectedID: UUID?
    var showsNewChatForm: Bool
    var draft: String
    var composerFocused: Bool
}

struct ChatBarLog: Equatable {
    var source: String
    var stage: String
    var detail: String
}

enum ChatBarEvent: Equatable {
    case send(String)
    case delta(String)
    case finish(String)
    case finishEmpty
    case stop
    case failure(String)
    case transcriptTap
    case selectHistory(UUID)
    case newChat
    case copy(String)
}

struct ChatBarEffect: Equatable {
    var state: ChatBarState
    var opensWindow: Bool
    var writes: Bool
    var log: ChatBarLog?
    var sendToModel: Bool
    var stopModel: Bool
}

struct ChatBarPresentedLine: Equatable {
    var id: String
    var role: HubLineRole
    var text: String
    var parsesAsMarkdown: Bool { role == .agent && !text.isEmpty }
}

struct ChatBarPresentation: Equatable {
    var status: HubTranscriptStatus
    var lines: [ChatBarPresentedLine]
}

struct ChatBarComposerChrome: Equatable {
    var placeholder: String
    var showsStop: Bool
    var sendEnabled: Bool
    var sendQuiet: Bool
}

struct ChatBarHistorySection: Equatable {
    var title: String
    var ids: [UUID]
}

struct ChatBarMotion: Equatable {
    var offset: Double
    var scale: Double
}

enum ChatBarPage {
    static let listWidth = 270.0
    static let emptyTitle = "New conversation"
    static let emptyDetail = "Chats stay in History on this Mac."
    static let newChatTitle = "New chat"
    static let composerPlaceholder = "Message Zeus"
    static let selectionOpacity = 0.12
    static let idleRowOpacity = 0.0
    static let sectionOrder = ["Pinned", "Today", "Yesterday", "Previous 7 days", "Older"]
    static let historyRowsUseStatusColor = false
    static let newChatAccentFill = false

    static func reduce(_ state: ChatBarState, _ event: ChatBarEvent, lineID: UUID = UUID()) -> ChatBarEffect {
        var state = state
        var writes = false
        var log: ChatBarLog?
        var sendToModel = false
        var stopModel = false

        switch event {
        case .send(let text):
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if spoken.isEmpty {
                log = ChatBarLog(source: "chat", stage: "idle", detail: "current")
            } else if state.transcript.status != .streaming {
                let effect = HubTranscriptMachine.reduce(state.transcript, .send, text: spoken, lineID: lineID)
                state.transcript = effect.transcript
                writes = effect.writes
                sendToModel = true
                state.draft = ""
            }
        case .delta(let text):
            let effect = HubTranscriptMachine.reduce(state.transcript, .delta, text: text, lineID: lineID)
            state.transcript = effect.transcript
            writes = effect.writes
        case .finish(let text):
            let effect = HubTranscriptMachine.reduce(state.transcript, .finish, text: text, lineID: lineID)
            writes = effect.writes
            state.transcript = effect.transcript
            if writes { log = ChatBarLog(source: "chat", stage: "settled", detail: "current") }
        case .finishEmpty:
            let effect = HubTranscriptMachine.reduce(state.transcript, .finishEmpty, text: "", lineID: lineID)
            writes = effect.writes
            state.transcript = effect.transcript
            if writes { log = ChatBarLog(source: "chat", stage: "failed", detail: "current") }
        case .stop:
            let kept = openAgentText(state.transcript.lines)
            let effect = HubTranscriptMachine.reduce(state.transcript, .stop, text: "", lineID: lineID)
            writes = effect.writes
            state.transcript = effect.transcript
            if writes {
                stopModel = true
                log = ChatBarLog(source: "chat", stage: kept ? "settled" : "stopped", detail: "current")
            }
        case .failure(let text):
            let effect = HubTranscriptMachine.reduce(state.transcript, .failure, text: text, lineID: lineID)
            writes = effect.writes
            state.transcript = effect.transcript
            if writes { log = ChatBarLog(source: "chat", stage: "failed", detail: "current") }
        case .transcriptTap:
            state.composerFocused = true
            log = ChatBarLog(source: "chat", stage: "tab", detail: "chat")
        case .selectHistory(let id):
            state.selectedID = id
            state.showsNewChatForm = false
            log = ChatBarLog(source: "chat", stage: "select", detail: "current")
        case .newChat:
            state.showsNewChatForm.toggle()
        case .copy:
            log = ChatBarLog(source: "chat", stage: "copy", detail: "current")
        }

        return ChatBarEffect(
            state: state,
            opensWindow: false,
            writes: writes,
            log: log,
            sendToModel: sendToModel,
            stopModel: stopModel
        )
    }

    static func present(messages: [ChatMessage], sending: Bool) -> ChatBarPresentation {
        let lines = messages.map { message -> ChatBarPresentedLine in
            let role: HubLineRole
            switch message.role {
            case .user:
                role = .person
            case .assistant:
                if message.failed {
                    role = .failed
                } else if isStopped(message.text) {
                    role = .stopped
                } else {
                    role = .agent
                }
            }
            return ChatBarPresentedLine(id: message.id.uuidString, role: role, text: message.text)
        }
        let status: HubTranscriptStatus
        if sending {
            status = .streaming
        } else if lines.last?.role == .failed {
            status = .failed
        } else if lines.isEmpty {
            status = .idle
        } else {
            status = .settled
        }
        return ChatBarPresentation(status: status, lines: lines)
    }

    /// The stored transcript the page table reads. Message ids round-trip, so a later delta keeps the line.
    static func transcript(messages: [ChatMessage], sending: Bool) -> HubTranscript {
        let presentation = present(messages: messages, sending: sending)
        let lines = presentation.lines.map { line in
            StoredTranscriptLine(
                id: UUID(uuidString: line.id) ?? UUID(),
                role: line.role,
                text: line.text,
                failed: line.role == .failed
            )
        }
        return HubTranscript(status: presentation.status, lines: lines)
    }

    static func composer(draft: String, sendingHere: Bool, busyElsewhere: Bool) -> ChatBarComposerChrome {
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let sendEnabled = !sendingHere && !busyElsewhere && !cleaned.isEmpty
        return ChatBarComposerChrome(
            placeholder: busyElsewhere ? "Zeus is answering in another chat" : composerPlaceholder,
            showsStop: sendingHere,
            sendEnabled: sendEnabled,
            sendQuiet: !sendEnabled
        )
    }

    static func history(_ conversations: [ChatConversation], now: Date = Date(), calendar: Calendar = .current) -> [ChatBarHistorySection] {
        ChatSection.group(conversations, now: now, calendar: calendar).map { group in
            ChatBarHistorySection(title: group.section.title, ids: group.conversations.map(\.id))
        }
    }

    static func motion(reduceMotion: Bool) -> ChatBarMotion {
        reduceMotion ? ChatBarMotion(offset: 0, scale: 1) : ChatBarMotion(offset: 8, scale: 0.985)
    }

    /// A non-empty chat, and a visual-only link, still go through the existing conversation JSON.
    static func save(_ conversation: ChatConversation, to store: ChatStore) throws {
        try store.save(conversation)
    }

    private static func isStopped(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Stopped." || trimmed == HubTranscriptNotice.stopped.storedLabel
    }

    private static func openAgentText(_ lines: [StoredTranscriptLine]) -> Bool {
        guard let open = lines.last, open.role == .agent, !open.failed else { return false }
        return !open.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#if canImport(ZeusCore)
typealias StoredTranscriptLine = ZeusCore.HubTranscriptLine
#else
typealias StoredTranscriptLine = HubTranscriptLine
#endif

#if canImport(SwiftUI)
import SwiftUI

/// Zeus's own conversation, inside the glass page. The composer sends, Stop shows while a reply
/// streams, and history is grouped. A tap on the transcript stays in the bar.
struct ChatPage: View {
    let chat: ChatModel
    @Bindable var hub: AgentHub = .shared
    @FocusState private var composerFocused: Bool

    var body: some View {
        if hub.creating {
            NewChatForm(hub: hub)
        } else {
            HStack(alignment: .top, spacing: 10) {
                historyColumn.frame(width: CGFloat(ChatBarPage.listWidth))
                Tile(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        transcript
                        composer
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func snapshot() -> ChatBarState {
        ChatBarState(
            transcript: ChatBarPage.transcript(messages: chat.current.messages, sending: chat.isSendingHere),
            selectedID: chat.currentID,
            showsNewChatForm: hub.creating,
            draft: chat.draft,
            composerFocused: composerFocused
        )
    }

    private func note(_ log: ChatBarLog?) {
        guard let log else { return }
        FlightRecorder.shared.record(log.source, log.stage, log.detail)
    }

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let effect = ChatBarPage.reduce(snapshot(), .newChat)
                note(effect.log)
                if effect.state.showsNewChatForm { hub.beginNewChat() } else { hub.creating = false }
            } label: {
                Text(ChatBarPage.newChatTitle)
                    .font(TopBarStyle.label(12, .semibold))
                    .foregroundStyle(Theme.cloudPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(ChatBarPage.newChatTitle)

            if chat.conversations.isEmpty {
                Text("No chats yet.")
                    .font(TopBarStyle.label(12))
                    .foregroundStyle(Theme.cloudQuiet)
                    .padding(.horizontal, 8)
            } else {
                PageScroll(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        let sections = ChatBarPage.history(chat.conversations)
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(TopBarStyle.label(10, .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Theme.cloudQuiet)
                                .padding(.top, 8)
                                .padding(.horizontal, 8)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.ids, id: \.self) { id in
                                if let conversation = chat.conversations.first(where: { $0.id == id }) {
                                    historyRow(conversation)
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History")
    }

    private func historyRow(_ conversation: ChatConversation) -> some View {
        let picked = conversation.id == chat.currentID
        return Button {
            let effect = ChatBarPage.reduce(snapshot(), .selectHistory(conversation.id))
            note(effect.log)
            chat.select(conversation.id)
            hub.creating = effect.state.showsNewChatForm
        } label: {
            Text(conversation.displayTitle)
                .font(TopBarStyle.label(12.5, picked ? .semibold : .regular))
                .foregroundStyle(picked ? Theme.cloudPrimary : Theme.cloudSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Color.white.opacity(picked ? ChatBarPage.selectionOpacity : ChatBarPage.idleRowOpacity),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(conversation.displayTitle)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var transcript: some View {
        let presentation = ChatBarPage.present(messages: chat.current.messages, sending: chat.isSendingHere)
        return VStack(alignment: .leading, spacing: 0) {
            if presentation.lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ChatBarPage.emptyTitle)
                        .font(TopBarStyle.label(13, .semibold))
                        .foregroundStyle(Theme.cloudPrimary)
                    Text(ChatBarPage.emptyDetail)
                        .font(TopBarStyle.label(11.5))
                        .foregroundStyle(Theme.cloudQuiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HubTranscriptView(
                    lines: presentation.lines.map { HubTranscriptLine(id: $0.id, role: $0.role, text: $0.text) },
                    status: presentation.status
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            let effect = ChatBarPage.reduce(snapshot(), .transcriptTap)
            note(effect.log)
            composerFocused = effect.state.composerFocused
        })
        .onChange(of: chat.isSendingHere) {
            guard !chat.isSendingHere else { return }
            let shown = ChatBarPage.present(messages: chat.current.messages, sending: false)
            let stage: String
            switch shown.lines.last?.role {
            case .failed: stage = "failed"
            case .stopped: stage = "stopped"
            default: stage = "settled"
            }
            FlightRecorder.shared.record("chat", stage, "current")
        }
    }

    private var composer: some View {
        let chrome = ChatBarPage.composer(draft: chat.draft, sendingHere: chat.isSendingHere, busyElsewhere: chat.busyElsewhere)
        return HStack(spacing: 8) {
            TextField(
                chrome.placeholder,
                text: Binding(get: { chat.draft }, set: { chat.draft = $0 }),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(TopBarStyle.label(12.5))
            .foregroundStyle(Theme.cloudPrimary)
            .lineLimit(1...4)
            .focused($composerFocused)
            .accessibilityIdentifier("chat.message")
            .onSubmit { submit() }
            if chrome.showsStop {
                mark(symbol: "stop.fill", label: "Stop", filled: true, action: stop)
            } else {
                mark(symbol: "arrow.up", label: "Send", filled: chrome.sendEnabled, action: submit)
                    .opacity(chrome.sendQuiet ? 0.4 : 1)
                    .disabled(!chrome.sendEnabled)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 30)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func mark(symbol: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Theme.cloudQuiet)
                .frame(width: 22, height: 22)
                .background(Circle().fill(filled ? Color.white : Color.white.opacity(0.10)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private func submit() {
        let effect = ChatBarPage.reduce(snapshot(), .send(chat.draft))
        note(effect.log)
        if effect.sendToModel { chat.send() }
    }

    private func stop() {
        let effect = ChatBarPage.reduce(snapshot(), .stop)
        note(effect.log)
        if effect.stopModel { chat.stop() }
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
#endif
