import Foundation
import Testing
@testable import ZeusCore

@Suite("Chat save keeps the draft")
struct ChatDiskSaveTests {
    @Test func failedSaveKeepsTheDraftAndSaysWhy() {
        let recovery = ChatDiskSave.recover(draft: "remember this", saved: false)
        #expect(recovery.draft == "remember this")
        #expect(recovery.notice == ChatDiskSave.notice)
    }

    @Test func successfulSaveClearsTheDraft() {
        let recovery = ChatDiskSave.recover(draft: "remember this", saved: true)
        #expect(recovery.draft == "")
        #expect(recovery.notice == nil)
    }

    @Test func storeCanBeToldToFailTheNextSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s06-chat-\(UUID().uuidString)", isDirectory: true)
        var store = ChatStore(root: root)
        store.failNextSave = true
        var conversation = ChatConversation(messages: [ChatMessage(role: .user, text: "hello")])
        conversation.id = UUID()
        #expect(throws: CocoaError.self) { try store.save(conversation) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("\(conversation.id.uuidString).json").path))
    }
}
