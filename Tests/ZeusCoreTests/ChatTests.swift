import Foundation
import Testing
@testable import ZeusCore

@Suite("Chat")
struct ChatTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func conversation(_ lines: [(ChatMessage.Role, String, Bool)]) -> ChatConversation {
        var chat = ChatConversation(createdAt: t0)
        for (offset, line) in lines.enumerated() {
            chat.append(ChatMessage(role: line.0, text: line.1, date: t0.addingTimeInterval(Double(offset)), failed: line.2))
        }
        return chat
    }

    @Test func titleComesFromFirstQuestion() {
        #expect(ChatConversation().displayTitle == ChatConversation.untitled)
        let chat = conversation([(.user, "What is the weather like in Paris this weekend for a picnic with friends?", false)])
        #expect(chat.displayTitle == "What is the weather like in Paris this weekend…")
        var named = chat
        named.title = "Picnic"
        #expect(named.displayTitle == "Picnic")
    }

    @Test func exchangesSkipFailuresAndPendingQuestions() {
        let chat = conversation([
            (.user, "one", false), (.assistant, "1", false),
            (.user, "two", false), (.assistant, "Claude is not reachable", true),
            (.user, "three", false), (.assistant, "3", false),
            (.user, "four", false),
        ])
        #expect(chat.exchanges() == [Exchange(user: "one", assistant: "1"), Exchange(user: "three", assistant: "3")])
        #expect(chat.exchanges(limit: 1) == [Exchange(user: "three", assistant: "3")])
    }

    @Test func updateReplacesStreamingText() {
        var chat = conversation([(.user, "hi", false)])
        let reply = ChatMessage(role: .assistant, text: "", date: t0.addingTimeInterval(5))
        chat.append(reply)
        chat.update(reply.id, text: "Hello there")
        #expect(chat.messages.last?.text == "Hello there")
        #expect(chat.updatedAt == t0.addingTimeInterval(5))
        #expect(chat.preview == "Hello there")
    }

    @Test func searchLooksAtTitleAndMessages() {
        let chat = conversation([(.user, "plan the trip", false), (.assistant, "Book the Eurostar early", false)])
        #expect(chat.matches("eurostar"))
        #expect(chat.matches("TRIP"))
        #expect(chat.matches(" "))
        #expect(!chat.matches("ferry"))
    }

    @Test func sectionsGroupByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = t0
        func chat(daysAgo: Double, pinned: Bool = false) -> ChatConversation {
            var c = ChatConversation(createdAt: now.addingTimeInterval(-daysAgo * 86_400))
            c.pinned = pinned
            return c
        }
        let items = [chat(daysAgo: 0), chat(daysAgo: 1), chat(daysAgo: 3), chat(daysAgo: 30), chat(daysAgo: 40, pinned: true)]
        let groups = ChatSection.group(items, now: now, calendar: calendar)
        #expect(groups.map(\.section) == [.pinned, .today, .yesterday, .week, .older])
        #expect(groups.allSatisfy { $0.conversations.count == 1 })
    }

    @Test func storeRoundTripsAndSkipsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ChatStore(root: dir)
        try store.save(ChatConversation())
        #expect(store.all().isEmpty)

        let older = conversation([(.user, "old", false)])
        var newer = ChatConversation(createdAt: t0.addingTimeInterval(100))
        newer.append(ChatMessage(role: .user, text: "new", date: t0.addingTimeInterval(100)))
        try store.save(older)
        try store.save(newer)
        #expect(store.all().map(\.id) == [newer.id, older.id])
        #expect(store.all().last == older)

        store.delete(newer.id)
        #expect(store.all().map(\.id) == [older.id])
    }

    @Test func visualOnlyLinkSurvivesStoreReloadWithoutInventingChatMessages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-chat-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = UUID()
        let conversation = ChatConversation(title: "A real visual explanation", createdAt: t0, visualExplanationID: link)
        let store = ChatStore(root: dir)
        try store.save(conversation)
        let reloaded = try #require(ChatStore(root: dir).all().first)
        #expect(reloaded.id == conversation.id && reloaded.visualExplanationID == link)
        #expect(reloaded.messages.isEmpty && reloaded.exchanges().isEmpty)
        #expect(reloaded.displayTitle == "A real visual explanation")
        store.delete(conversation.id)
        #expect(ChatStore(root: dir).all().isEmpty)
    }

    @Test func legacyConversationWithoutVisualLinkStillDecodesAndUnlinkedEmptyStaysUnsaved() throws {
        let conversation = conversation([(.user, "An older conversation", false)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(conversation)
        let decodedJSON = try JSONSerialization.jsonObject(with: encoded)
        var legacy = try #require(decodedJSON as? [String: Any])
        legacy.removeValue(forKey: "visualExplanationID")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatConversation.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded == conversation && decoded.visualExplanationID == nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-chat-unlinked-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ChatStore(root: dir)
        try store.save(ChatConversation(title: "An unsent draft"))
        #expect(store.all().isEmpty && !FileManager.default.fileExists(atPath: dir.path))
    }
}
