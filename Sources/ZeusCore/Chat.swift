import Foundation

/// One line in a typed conversation with ZEUS.
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    public var date: Date
    /// The reply failed; the text is the error shown to the person, never sent back as history.
    public var failed: Bool
    /// Which engine wrote a reply (`RouterEngine` raw value) and why; nil in older chats.
    public var engine: String?
    public var engineReason: String?

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), failed: Bool = false,
                engine: String? = nil, engineReason: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.failed = failed
        self.engine = engine
        self.engineReason = engineReason
    }
}

/// A conversation, shared by the notch Chat tab and the floating chat window.
public struct ChatConversation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]
    public var pinned: Bool
    /// A real local explanation record linked from this sidebar entry. Optional
    /// decoding keeps existing Chat JSON compatible without inventing messages.
    public var visualExplanationID: UUID?

    public init(id: UUID = UUID(), title: String = "", createdAt: Date = Date(), messages: [ChatMessage] = [], pinned: Bool = false,
                visualExplanationID: UUID? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = messages.last?.date ?? createdAt
        self.messages = messages
        self.pinned = pinned
        self.visualExplanationID = visualExplanationID
    }

    public static let untitled = "New chat"

    /// The stored title, else the first thing the person asked, cut at a word near 48 characters.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard let first = messages.first(where: { $0.role == .user })?.text else { return Self.untitled }
        return Self.shorten(first, to: 48)
    }

    public var preview: String {
        guard let last = messages.last(where: { !$0.failed }) else { return "" }
        return Self.shorten(last.text, to: 80)
    }

    public var isEmpty: Bool { messages.isEmpty }

    public mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = message.date
    }

    /// Replaces the text of a message being streamed in.
    public mutating func update(_ id: UUID, text: String, failed: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
        messages[index].failed = failed
    }

    /// Finished user/assistant pairs for the model, newest `limit` only. Failed replies and
    /// a question still waiting for its answer are left out.
    public func exchanges(limit: Int = 10) -> [Exchange] {
        var pairs: [Exchange] = []
        var pendingUser: String?
        for message in messages {
            switch message.role {
            case .user:
                pendingUser = message.text
            case .assistant:
                if let user = pendingUser, !message.failed, !message.text.isEmpty {
                    pairs.append(Exchange(user: user, assistant: message.text))
                }
                pendingUser = nil
            }
        }
        return Array(pairs.suffix(limit))
    }

    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return displayTitle.localizedCaseInsensitiveContains(needle)
            || messages.contains { $0.text.localizedCaseInsensitiveContains(needle) }
    }

    static func shorten(_ text: String, to limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        let base = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return base.trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Sidebar sections, the way chat apps group history.
public enum ChatSection: String, CaseIterable, Sendable {
    case pinned, today, yesterday, week, older

    public var title: String {
        switch self {
        case .pinned: "Pinned"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Previous 7 days"
        case .older: "Older"
        }
    }

    public static func of(_ conversation: ChatConversation, now: Date, calendar: Calendar = .current) -> ChatSection {
        if conversation.pinned { return .pinned }
        let date = conversation.updatedAt
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= weekAgo { return .week }
        return .older
    }

    /// Non-empty sections in display order, newest conversation first inside each.
    public static func group(_ conversations: [ChatConversation], now: Date = Date(), calendar: Calendar = .current)
        -> [(section: ChatSection, conversations: [ChatConversation])] {
        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }
        let buckets = Dictionary(grouping: sorted) { of($0, now: now, calendar: calendar) }
        return allCases.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }
}

/// Conversations as JSON files under one folder (`chats/<id>.json`), on this Mac only.
public struct ChatStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var standard: ChatStore {
        ChatStore(root: ZeusPaths.supportDirectory.appendingPathComponent("chats", isDirectory: true))
    }

    private func url(for id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json") }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Empty, unlinked conversations are never written, so opening the window
    /// doesn't litter history. Visual-only conversations retain their actual record link.
    public func save(_ conversation: ChatConversation) throws {
        guard !conversation.isEmpty || conversation.visualExplanationID != nil else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder().encode(conversation).write(to: url(for: conversation.id), options: .atomic)
    }

    /// Newest first.
    public func all() -> [ChatConversation] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder().decode(ChatConversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
