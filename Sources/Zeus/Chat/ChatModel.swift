import AppKit
import Observation
import ZeusCore

/// The one chat state behind both the notch Chat tab and the floating chat window, so a
/// conversation started in one is already open in the other.
@MainActor
@Observable
final class ChatModel {
    static let shared = ChatModel()

    private(set) var conversations: [ChatConversation] = []
    private(set) var currentID: UUID?
    var draft = ""
    var search = ""
    private(set) var isSending = false
    /// The conversation the in-flight answer belongs to.
    private(set) var sendingID: UUID?
    /// Set by the app delegate; nil in snapshots and tests.
    var brain: BrainProvider?
    /// Opens (or brings forward) the floating window with the composer focused.
    var openWindow: () -> Void = {}
    /// The visual explanation store removes its linked local record with Chat.
    var onDeleteConversation: (UUID, UUID) -> Void = { _, _ in }
    private var failedVisualLinkIDs = Set<UUID>()
    private var visualLinkProblem: String?
    var hasUnsavedVisualLinks: Bool { !failedVisualLinkIDs.isEmpty }
    var visualStoreError: String? {
        if hasUnsavedVisualLinks {
            return "Some explanation sidebar links could not be saved. Keep Zeus open and check local storage before quitting."
        }
        return visualLinkProblem
    }

    private let store: ChatStore
    private var turn: UUID?
    /// The engine answering right now (may differ from `brain` when the router picked another).
    private var activeBrain: BrainProvider?
    private var sendTask: Task<Void, Never>?
    /// Unsaved new chat, kept apart so an empty one never appears in history.
    private var scratch = ChatConversation()

    init(store: ChatStore = .standard) {
        self.store = store
        conversations = store.all()
        currentID = conversations.first?.id
    }

    var current: ChatConversation {
        guard let currentID, let found = conversations.first(where: { $0.id == currentID }) else { return scratch }
        return found
    }

    /// An answer is being written into the chat that is open now (Stop belongs to this chat only).
    var isSendingHere: Bool { isSending && sendingID == current.id }

    /// An answer is being written, but into a different chat than the open one.
    var busyElsewhere: Bool { isSending && sendingID != current.id }

    func isSending(in id: UUID) -> Bool { isSending && sendingID == id }

    var filtered: [ChatConversation] { conversations.filter { $0.matches(search) } }

    var sections: [(section: ChatSection, conversations: [ChatConversation])] { ChatSection.group(filtered) }

    /// Switching chats leaves an in-flight answer running: it writes into its own conversation by id,
    /// so only Stop or deleting that conversation cancels it.
    func newChat() {
        scratch = ChatConversation()
        currentID = nil
        draft = ""
    }

    func select(_ id: UUID) {
        guard id != currentID else { return }
        currentID = id
    }

    func delete(_ id: UUID) {
        let visualLink = conversations.first(where: { $0.id == id })?.visualExplanationID
        if id == sendingID { stop() }
        failedVisualLinkIDs.remove(id)
        store.delete(id)
        conversations.removeAll { $0.id == id }
        if id == currentID { currentID = conversations.first?.id }
        if let visualLink { onDeleteConversation(id, visualLink) }
    }

    /// Retains a visual conversation in the existing sidebar without routing its
    /// request through the action-capable ordinary Chat send path.
    @discardableResult
    func retainVisualConversation(title: String, explanationID: UUID, conversationID: UUID) -> Bool {
        let isCurrent = current.id == conversationID
        guard var conversation = isCurrent ? current : conversations.first(where: { $0.id == conversationID }) else {
            visualLinkProblem = "The explanation's conversation is no longer available. Its sidebar link was not recreated."
            return false
        }
        if conversation.title.isEmpty {
            conversation.title = String(title.prefix(80))
        }
        conversation.visualExplanationID = explanationID
        conversation.updatedAt = Date()
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        if isCurrent { currentID = conversationID }
        do {
            try store.save(conversation)
            failedVisualLinkIDs.remove(conversationID)
            visualLinkProblem = nil
            return true
        } catch {
            failedVisualLinkIDs.insert(conversationID)
            return false
        }
    }

    /// One explicit retry per pending link, using the current conversation rather
    /// than an old snapshot. Deleting a conversation removes its retry admission.
    func retryVisualConversationLinks() {
        for id in Array(failedVisualLinkIDs) {
            guard let conversation = conversations.first(where: { $0.id == id }), conversation.visualExplanationID != nil else {
                failedVisualLinkIDs.remove(id)
                continue
            }
            do { try store.save(conversation); failedVisualLinkIDs.remove(id) }
            catch { /* Keep this exact unsaved link visible and eligible for a later retry. */ }
        }
    }

    func togglePin(_ id: UUID) {
        mutate(id) { $0.pinned.toggle() }
    }

    func rename(_ id: UUID, to title: String) {
        mutate(id) { $0.title = title }
    }

    /// Cancels the reply being written; what arrived so far stays.
    func stop() {
        sendTask?.cancel()
        sendTask = nil
        // Stopped before the first word: the empty bubble says so now instead of waiting for the task to wind down.
        if let id = sendingID {
            mutate(id) { conversation in
                if let last = conversation.messages.last, last.role == .assistant, last.text.isEmpty {
                    conversation.update(last.id, text: "Stopped.")
                }
            }
        }
        if let turn, let active = activeBrain ?? brain { Task { await active.cancel(turn: turn) } }
        turn = nil
        sendingID = nil
        isSending = false
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        var conversation = current
        let history = conversation.exchanges()
        conversation.append(ChatMessage(role: .user, text: text))
        if let spoken = InstantTable.spokenAnswer(for: text) {
            conversation.append(ChatMessage(role: .assistant, text: spoken, engine: "local", engineReason: "Instant"))
            upsert(conversation)
            return
        }
        if case .fastCommand = InstantTable.route(text), let intent = FastIntent.parse(text) {
            switch FastActions.shared.resolve(intent) {
            case .plan(let plan):
                let ack = plan.ack ?? plan.summary
                conversation.append(ChatMessage(role: .assistant, text: ack, engine: "local", engineReason: "Instant"))
                upsert(conversation)
                Task { _ = await plan.run { } }
                return
            case .ask(let question):
                conversation.append(ChatMessage(role: .assistant, text: question, engine: "local", engineReason: "Instant"))
                upsert(conversation)
                return
            case .pass:
                break
            }
        }
        // The router picks the engine for this kind of task (Settings › Intelligence).
        let (routed, decision) = RouterSettings.shared.provider(for: text, claude: brain)
        // `provider(for:)` falls back to Claude when the picked CLI isn't installed: label the engine that really answers.
        let picked = decision.engine
        let fellBack = picked != nil && picked != .claude && RouterSettings.shared.installed[picked!] == nil
        let answering = fellBack ? RouterEngine.claude : picked
        let reply = ChatMessage(role: .assistant, text: "", engine: answering?.rawValue,
                                engineReason: fellBack ? "\(picked!.title) isn't installed, so Claude answered." : decision.reason)
        conversation.append(reply)
        upsert(conversation)

        guard let brain = routed else {
            let message = answering == nil ? decision.reason : "ZEUS isn't connected to \(answering!.title) yet. Open Setup to connect it."
            mutate(conversation.id) { $0.update(reply.id, text: message, failed: true) }
            return
        }
        activeBrain = brain
        let turn = UUID()
        self.turn = turn
        isSending = true
        sendingID = conversation.id
        let request = BrainRequest(turn: turn, transcript: text, axSummary: VoiceTurnController.context(),
                                   history: history, systemPrompt: ChatPrompt.system)
        let id = conversation.id
        sendTask = Task { [weak self] in
            var parser = ZeusTagStreamParser()
            var written = ""
            func absorb(_ outputs: [ZeusTagStreamParser.Output]) {
                for case .text(let piece) in outputs { written += piece }
            }
            do {
                for try await event in brain.send(request) {
                    if Task.isCancelled { break }
                    guard case .textDelta(let delta) = event else { continue }
                    absorb(parser.feed(delta))
                    let shown = written.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.mutate(id, save: false) { $0.update(reply.id, text: shown) }
                }
                absorb(parser.finish())
                let final = written.trimmingCharacters(in: .whitespacesAndNewlines)
                if Task.isCancelled {
                    // Stop ends the stream quietly; before the first word that is "Stopped.", not a missing answer.
                    self?.mutate(id) { $0.update(reply.id, text: final.isEmpty ? "Stopped." : final) }
                } else {
                    self?.mutate(id) { $0.update(reply.id, text: final.isEmpty ? "No answer came back." : final, failed: final.isEmpty) }
                }
            } catch {
                let partial = written.trimmingCharacters(in: .whitespacesAndNewlines)
                if Task.isCancelled {
                    self?.mutate(id) { $0.update(reply.id, text: partial.isEmpty ? "Stopped." : partial) }
                } else {
                    self?.mutate(id) { $0.update(reply.id, text: VoiceTurnController.spokenError(error), failed: true) }
                }
            }
            guard let self, self.turn == turn else { return }
            self.turn = nil
            self.sendingID = nil
            self.isSending = false
        }
    }

    /// A finished exchange that happened elsewhere (a research report, say) saved as its own chat,
    /// so it shows up in the notch Chat tab and the floating window.
    func recordExchange(user: String, assistant: String, engine: String? = nil) {
        let now = Date()
        let conversation = ChatConversation(createdAt: now, messages: [
            ChatMessage(role: .user, text: user, date: now),
            ChatMessage(role: .assistant, text: assistant, date: now, engine: nil, engineReason: engine.map { "Answered by \($0)" }),
        ])
        conversations.insert(conversation, at: 0)
        try? store.save(conversation)
    }

    // MARK: Storage

    private func upsert(_ conversation: ChatConversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        currentID = conversation.id
        try? store.save(conversation)
    }

    private func mutate(_ id: UUID, save: Bool = true, _ change: (inout ChatConversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[index])
        if save { try? store.save(conversations[index]) }
    }
}

enum ChatPrompt {
    static var system: String { system(personality: .current()) }

    static func system(personality: ZeusPersonality) -> String { """
    You are ZEUS, an assistant that lives on Tony's Mac. This conversation is typed in the ZEUS \
    chat window, not spoken. Answer in text: be direct and useful, use short Markdown (bold, \
    lists, inline code) when it helps, and answer in the language Tony wrote in. Do not use \
    [POINT], [HIGHLIGHT] or [ACTION] tags here; there is no screen pointing in chat.

    \(ZeusPersona.instructions(for: personality))
    In chat, length follows the question; the manner stays.
    """ }
}
