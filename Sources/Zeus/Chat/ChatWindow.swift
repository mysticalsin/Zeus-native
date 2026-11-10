import AppKit
import SwiftUI
import ZeusCore

/// The floating chat window: history on the left, the conversation on the right, in the
/// notch's own dark glass. It floats over other apps and remembers where it was.
@MainActor
final class ChatWindowController {
    private var window: NSPanel?
    private let chat: ChatModel
    var makeExplanation: () -> ExplanationController? = { nil }
    var stopExplanation: () -> Void = {}

    init(chat: ChatModel = .shared) {
        self.chat = chat
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let panel = ChatPanel(contentRect: CGRect(x: 0, y: 0, width: 680, height: 520),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        panel.title = "ZEUS Chat"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        panel.onHide = { [weak self] in self?.stopExplanation() }
        panel.hidesOnDeactivate = false
        panel.backgroundColor = NSColor(Theme.storm)
        panel.minSize = CGSize(width: 480, height: 360)
        panel.contentView = NSHostingView(rootView: ChatWindowView(chat: chat, makeExplanation: makeExplanation))
        if !panel.setFrameUsingName("ZeusChat") { panel.center() }
        panel.setFrameAutosaveName("ZeusChat")
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = panel
    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow { window.orderOut(nil) } else { show() }
    }
}

final class ChatPanel: NSPanel {
    /// Explicit AppKit lifecycle: a retained hosting view is not guaranteed to
    /// receive SwiftUI onDisappear when its window is hidden or miniaturized.
    var onHide: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func orderOut(_ sender: Any?) { onHide(); super.orderOut(sender) }
    override func close() { onHide(); super.close() }
    override func miniaturize(_ sender: Any?) { onHide(); super.miniaturize(sender) }
}

struct ChatWindowView: View {
    let chat: ChatModel
    var makeExplanation: () -> ExplanationController? = { nil }
    @AppStorage("opt.explanation.enabled") private var visualEnabled = "false"
    @State private var showingVisual = false
    @State private var explanation: ExplanationController?

    var body: some View {
        HStack(spacing: 0) {
            ChatSidebar(chat: chat)
                .frame(width: 210)
            Rectangle().fill(TopBarStyle.tileStroke).frame(width: 1)
            VStack(spacing: 0) {
                if visualEnabled == "true" {
                    HStack {
                        Button("Conversation") { showingVisual = false; explanation?.stop() }
                            .buttonStyle(.borderless)
                        Button { if explanation == nil { explanation = makeExplanation() }; showingVisual = true } label: {
                            Label("Visual explanation", systemImage: "square.on.circle")
                        }.buttonStyle(.borderless)
                        Spacer()
                    }.font(TopBarStyle.label(11, .semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                    Divider()
                }
                if let error = chat.visualStoreError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.vertical, 8)
                        .accessibilityIdentifier("explanation.sidebar-save-error")
                }
                if showingVisual, visualEnabled == "true", let explanation {
                    ExplanationPane(controller: explanation, conversationID: chat.current.id) {
                        explanation.submit()
                    }
                } else {
                    ChatTranscriptView(chat: chat, compact: false)
                    ChatComposer(chat: chat, compact: false).padding(12)
                }
            }
        }
        .padding(.top, 28)
        .background(Theme.storm)
        .preferredColorScheme(.dark)
        .onChange(of: visualEnabled) { if visualEnabled != "true" { explanation?.stop(); showingVisual = false } }
    }
}

private struct ChatSidebar: View {
    let chat: ChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cloudQuiet)
                TextField("Search", text: Binding(get: { chat.search }, set: { chat.search = $0 }))
                    .textFieldStyle(.plain).font(TopBarStyle.label(12)).foregroundStyle(Theme.cloudPrimary)
                GlyphButton(symbol: "square.and.pencil", size: 11, tint: Theme.bolt, label: "New chat") { chat.newChat() }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(chat.sections, id: \.section) { group in
                        Text(group.section.title.uppercased())
                            .font(TopBarStyle.label(9.5, .bold)).foregroundStyle(Theme.cloudQuiet)
                            .padding(.top, 8).padding(.horizontal, 6)
                        ForEach(group.conversations) { conversation in
                            ChatHistoryRow(chat: chat, conversation: conversation)
                        }
                    }
                    if chat.conversations.isEmpty {
                        Text("Your chats appear here, on this Mac only.")
                            .font(TopBarStyle.label(11)).foregroundStyle(Theme.cloudQuiet).padding(6)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(10)
    }
}

private struct ChatHistoryRow: View {
    let chat: ChatModel
    let conversation: ChatConversation

    var body: some View {
        let selected = chat.currentID == conversation.id
        Button { chat.select(conversation.id) } label: {
            HStack(spacing: 6) {
                if conversation.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.bolt)
                }
                Text(conversation.displayTitle)
                    .font(TopBarStyle.label(11.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.cloudPrimary : Theme.cloudSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(selected ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(conversation.pinned ? "Unpin" : "Pin") { chat.togglePin(conversation.id) }
            Button("Copy conversation") {
                let text = conversation.messages.map { "\($0.role == .user ? "You" : "ZEUS"): \($0.text)" }.joined(separator: "\n\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { chat.delete(conversation.id) }
        }
    }
}

/// Messages of the current conversation. `compact` is the notch's three-line view.
struct ChatTranscriptView: View {
    let chat: ChatModel
    let compact: Bool

    var body: some View {
        let conversation = chat.current
        if compact {
            // The notch shows the latest lines without scrolling, newest at the bottom.
            VStack(alignment: .leading, spacing: 5) {
                Spacer(minLength: 0)
                if conversation.messages.isEmpty { ChatEmptyState(compact: true) }
                ForEach(conversation.messages.suffix(3)) { message in
                    ChatBubble(message: message, compact: true, writing: chat.isSendingHere && message.id == conversation.messages.last?.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if conversation.messages.isEmpty { ChatEmptyState(compact: false) }
                        ForEach(conversation.messages) { message in
                            ChatBubble(message: message, compact: false, writing: chat.isSendingHere && message.id == conversation.messages.last?.id)
                                .id(message.id)
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.never)
                .onChange(of: conversation.messages.last?.text) {
                    guard let last = conversation.messages.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                .onAppear {
                    if let last = conversation.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

private struct ChatEmptyState: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("New conversation").font(TopBarStyle.label(compact ? 12 : 15, .semibold)).foregroundStyle(Theme.cloudPrimary)
            }
            Text("Chats stay in History on this Mac.")
                .font(TopBarStyle.label(compact ? 10 : 11.5)).foregroundStyle(Theme.cloudQuiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, compact ? 0 : 40)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let compact: Bool
    let writing: Bool

    var body: some View {
        let isUser = message.role == .user
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: compact ? 30 : 60) }
            Group {
                if message.text.isEmpty && writing {
                    LevelBars(color: Theme.bolt, active: true, height: compact ? 8 : 10)
                } else if !isUser, !compact, !message.failed {
                    // Full replies get lists, headings and code blocks.
                    MarkdownBlocksView(text: message.text, size: 13)
                        .textSelection(.enabled)
                } else {
                    Text(Self.markdown(message.text))
                        .font(TopBarStyle.label(compact ? 11 : 13))
                        .foregroundStyle(message.failed ? Theme.danger : (isUser ? Theme.storm : Theme.cloudPrimary))
                        .lineLimit(compact ? 3 : nil)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 5 : 8)
            .background(isUser ? Theme.cloudPrimary : TopBarStyle.tile,
                        in: RoundedRectangle(cornerRadius: compact ? 9 : Theme.cardRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUser, !compact, let engine = message.engine.flatMap(RouterEngine.init(rawValue:)) {
                    RouterEngineBadge(engine: engine, reason: message.engineReason).offset(x: 6, y: 9)
                }
            }
            if !isUser { Spacer(minLength: compact ? 30 : 60) }
        }
        .transition(.opacity.combined(with: .offset(y: 4)))
        .contextMenu {
            if !message.text.isEmpty, !message.failed {
                Button("Make Sticky") { StickiesController.shared.new(text: message.text) }
                Button("Save to Brain…") {
                    BrainCaptureWindow.shared.show(title: StickyNote(text: message.text).title, body: message.text, source: "chat")
                }
            }
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

struct ChatComposer: View {
    let chat: ChatModel
    let compact: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(chat.busyElsewhere ? "ZEUS is answering in another chat" : "Message",
                      text: Binding(get: { chat.draft }, set: { chat.draft = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(TopBarStyle.label(13))
                .foregroundStyle(Theme.cloudPrimary)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { chat.send() }
            if chat.isSendingHere {
                GlyphButton(symbol: "stop.fill", size: 11, tint: Theme.cloudPrimary, label: "Stop") { chat.stop() }
            } else {
                // Another chat's answer is still being written: Send waits for it, and Stop stays on that chat.
                let ready = !chat.draft.isEmpty && !chat.busyElsewhere
                GlyphButton(symbol: "arrow.up", size: 11, tint: ready ? Theme.bolt : Theme.cloudQuiet, label: "Send") { chat.send() }
            }
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
        .background(TopBarStyle.tile, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(focused ? Theme.bolt.opacity(0.5) : TopBarStyle.tileStroke))
        .onAppear { focused = true }
    }
}
