import AppKit
import Foundation
import Testing
import ZeusCore
@testable import Zeus

/// Disposable stores and this test's own NSPanel only. No capture, permissions,
/// user preferences, providers, global input or external windows are accessed.
@MainActor @Suite("Explanation Chat links and owned window lifecycle", .serialized)
struct ExplanationChatLifecycleTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-explanation-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func ordinaryChatDeletionDoesNotAdmitExplanationStorageWork() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(root: root)
        var ordinary = ChatConversation()
        ordinary.append(.init(role: .user, text: "Synthetic ordinary chat"))
        try store.save(ordinary)
        let model = ChatModel(store: store)
        var deleted: [UUID] = []
        model.onDeleteConversation = { id, _ in deleted.append(id) }
        model.delete(ordinary.id)
        #expect(deleted.isEmpty)
        model.newChat()
        let visual = model.current.id
        #expect(model.retainVisualConversation(title: "Synthetic scene", explanationID: UUID(), conversationID: visual))
        model.delete(visual)
        #expect(deleted == [visual])
    }

    @Test func linksRemainBoundToTheirConversationWithoutChangingSelectionOrInventingMessages() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(root: root), model = ChatModel(store: store)
        let first = model.current.id, firstLink = UUID()
        #expect(model.retainVisualConversation(title: "First scene", explanationID: firstLink, conversationID: first))
        model.newChat()
        let second = model.current.id, secondLink = UUID()
        #expect(model.retainVisualConversation(title: "Second scene", explanationID: secondLink, conversationID: second))
        #expect(model.retainVisualConversation(title: "First follow-up", explanationID: firstLink, conversationID: first))
        #expect(model.current.id == second)
        let reloaded = ChatModel(store: store)
        #expect(reloaded.conversations.count == 2 && reloaded.conversations.allSatisfy { $0.messages.isEmpty })
        #expect(reloaded.conversations.first(where: { $0.id == first })?.visualExplanationID == firstLink)
        let unknown = UUID()
        #expect(!model.retainVisualConversation(title: "Removed", explanationID: UUID(), conversationID: unknown))
        #expect(model.current.id == second && !model.conversations.contains(where: { $0.id == unknown }))
    }

    @Test func aSuccessfulOtherLinkCannotHideAFailedLinkAndRetryUsesCurrentConversation() throws {
        let root = try directory(), blocked = root.appendingPathComponent("chats")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: blocked)
        let store = ChatStore(root: blocked), model = ChatModel(store: store)
        let first = model.current.id, firstLink = UUID()
        #expect(!model.retainVisualConversation(title: "Unsaved scene", explanationID: firstLink, conversationID: first))
        #expect(model.hasUnsavedVisualLinks && model.visualStoreError != nil)
        model.rename(first, to: "Latest in-memory title")
        try FileManager.default.removeItem(at: blocked)
        model.newChat()
        let second = model.current.id
        #expect(model.retainVisualConversation(title: "Saved scene", explanationID: UUID(), conversationID: second))
        #expect(model.hasUnsavedVisualLinks && model.visualStoreError != nil)
        model.retryVisualConversationLinks()
        #expect(!model.hasUnsavedVisualLinks && model.visualStoreError == nil && model.current.id == second)
        let saved = try #require(store.all().first(where: { $0.id == first }))
        #expect(saved.title == "Latest in-memory title" && saved.visualExplanationID == firstLink)
    }

    @Test func deletingAFailedLinkRemovesItsRetryAdmission() throws {
        let root = try directory(), blocked = root.appendingPathComponent("chats")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: blocked)
        let store = ChatStore(root: blocked), model = ChatModel(store: store)
        let id = model.current.id
        #expect(!model.retainVisualConversation(title: "Deleted scene", explanationID: UUID(), conversationID: id))
        model.delete(id)
        #expect(!model.hasUnsavedVisualLinks)
        try FileManager.default.removeItem(at: blocked)
        model.retryVisualConversationLinks()
        #expect(store.all().isEmpty && !model.conversations.contains(where: { $0.id == id }))
    }

    @Test func ownedPanelHideCloseMiniaturizeAndEscapeSynchronouslyNotifyStop() {
        _ = NSApplication.shared
        for route in ["hide", "close", "miniaturize", "escape"] {
            let panel = ChatPanel(contentRect: .init(x: 0, y: 0, width: 180, height: 80),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            var timeline: [String] = []
            panel.onHide = { timeline.append("stop") }
            switch route {
            case "hide": panel.orderOut(nil)
            case "close": panel.close()
            case "miniaturize": panel.miniaturize(nil)
            default: panel.cancelOperation(nil)
            }
            timeline.append("returned")
            // AppKit may route close through orderOut as well. The production
            // controller's stop is idempotent; every notification precedes return.
            #expect(timeline.count >= 2 && timeline.first == "stop" && timeline.last == "returned")
            #expect(timeline.dropLast().allSatisfy { $0 == "stop" })
            panel.onHide = {}
            panel.close()
        }
    }
}
