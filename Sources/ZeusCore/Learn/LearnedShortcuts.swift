import Foundation

/// One verified "when I say X, do Y". Steps stay short and carry no screen coordinates.
public struct LearnedShortcut: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var phrase: String
    public var steps: [String]
    public var savedAt: Date

    public init(id: UUID = UUID(), phrase: String, steps: [String], savedAt: Date = Date()) {
        self.id = id
        self.phrase = phrase
        self.steps = steps
        self.savedAt = savedAt
    }

    public static let maxCharacters = 600

    public static func hasCoordinates(_ text: String) -> Bool {
        text.range(of: #"\d+\s*,\s*\d+"#, options: .regularExpression) != nil
    }

    public var body: String { steps.joined(separator: "\n") }
}

public enum LearnSave: Equatable, Sendable {
    case saved(LearnedShortcut)
    case rejected(String)
}

public struct LearnedBook: Codable, Equatable, Sendable {
    public var items: [LearnedShortcut]
    public var history: [[LearnedShortcut]]

    public init(items: [LearnedShortcut] = [], history: [[LearnedShortcut]] = []) {
        self.items = items
        self.history = history
    }
}

/// Saves only a verified run. Undo restores the list from before the last save or removal.
public struct LearnedShortcutStore: Equatable, Sendable {
    public private(set) var book: LearnedBook

    public init(book: LearnedBook = LearnedBook()) {
        self.book = book
    }

    public var items: [LearnedShortcut] { book.items }

    public func match(_ phrase: String) -> LearnedShortcut? {
        let key = Self.normalize(phrase)
        return book.items.first { Self.normalize($0.phrase) == key }
    }

    @discardableResult
    public mutating func save(phrase: String, steps: [String], verified: Bool, at: Date = Date()) -> LearnSave {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard verified else { return .rejected("unverified") }
        guard !phrase.isEmpty, !steps.isEmpty else { return .rejected("empty") }
        let shortcut = LearnedShortcut(phrase: phrase, steps: steps, savedAt: at)
        guard shortcut.body.count <= LearnedShortcut.maxCharacters else { return .rejected("too long") }
        guard !LearnedShortcut.hasCoordinates(shortcut.body) else { return .rejected("coordinates") }
        push()
        book.items.removeAll { Self.normalize($0.phrase) == Self.normalize(phrase) }
        book.items.append(shortcut)
        return .saved(shortcut)
    }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        guard book.items.contains(where: { $0.id == id }) else { return false }
        push()
        book.items.removeAll { $0.id == id }
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = book.history.popLast() else { return false }
        book.items = previous
        return true
    }

    public static func load(from url: URL) -> LearnedShortcutStore {
        guard let data = try? Data(contentsOf: url), let book = try? JSONDecoder().decode(LearnedBook.self, from: data) else {
            return LearnedShortcutStore()
        }
        return LearnedShortcutStore(book: book)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(book)
        try data.write(to: url)
    }

    private mutating func push() {
        book.history.append(book.items)
        if book.history.count > 20 { book.history.removeFirst(book.history.count - 20) }
    }

    static func normalize(_ phrase: String) -> String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum NamedShortcutPhrase {
    /// "When I say focus mode, close Slack and open Notes".
    public static func parse(_ text: String) -> (phrase: String, steps: [String])? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let prefix = "when i say "
        guard lower.hasPrefix(prefix) else { return nil }
        var rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase: String
        let action: String
        if let comma = rest.firstIndex(of: ",") {
            phrase = String(rest[..<comma]).trimmingCharacters(in: .whitespaces)
            action = String(rest[rest.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        } else if let range = rest.lowercased().range(of: " do ") {
            phrase = String(rest[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            action = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        var stepsText = action
        if stepsText.lowercased().hasPrefix("do ") { stepsText = String(stepsText.dropFirst(3)) }
        let steps = stepsText
            .replacingOccurrences(of: " then ", with: " and ")
            .components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !phrase.isEmpty, !steps.isEmpty else { return nil }
        return (phrase, steps)
    }
}

public enum LearnResult: Equatable, Sendable {
    case replayed
    case fallback
    case brain([String])
}

/// A saved shortcut replays with no model call. A failed step is forgotten and the brain runs once.
public struct LearnEngine: Equatable, Sendable {
    public private(set) var llmCalls = 0

    public init() {}

    @discardableResult
    public mutating func run(phrase: String, store: inout LearnedShortcutStore, perform: (String) -> Bool, brain: () -> [String]) -> LearnResult {
        if let shortcut = store.match(phrase) {
            for step in shortcut.steps {
                if !perform(step) {
                    store.remove(shortcut.id)
                    llmCalls += 1
                    _ = brain()
                    return .fallback
                }
            }
            return .replayed
        }
        llmCalls += 1
        return .brain(brain())
    }
}

/// The shortcuts Zeus shows in Settings. Tests use `LearnedShortcutStore` directly.
public final class LearnedShortcutDisk: @unchecked Sendable {
    public static let shared = LearnedShortcutDisk()

    private let lock = NSLock()
    private var store: LearnedShortcutStore
    private let url: URL

    public init(url: URL = ZeusPaths.learnedShortcuts) {
        self.url = url
        store = LearnedShortcutStore.load(from: url)
    }

    public func list() -> [LearnedShortcut] {
        lock.lock(); defer { lock.unlock() }
        return store.items
    }

    public func match(_ phrase: String) -> LearnedShortcut? {
        lock.lock(); defer { lock.unlock() }
        return store.match(phrase)
    }

    @discardableResult
    public func save(phrase: String, steps: [String], verified: Bool) -> LearnSave {
        lock.lock(); defer { lock.unlock() }
        let result = store.save(phrase: phrase, steps: steps, verified: verified)
        if case .saved = result { try? store.write(to: url) }
        return result
    }

    @discardableResult
    public func remove(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard store.remove(id) else { return false }
        try? store.write(to: url)
        return true
    }

    @discardableResult
    public func undo() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard store.undo() else { return false }
        try? store.write(to: url)
        return true
    }
}

public enum LearnAcceptance {
    public static func report() -> (text: String, passed: Bool) {
        var store = LearnedShortcutStore()
        var engine = LearnEngine()
        var problems: [String] = []
        guard let parsed = NamedShortcutPhrase.parse("When I say focus mode, close Slack and open Notes") else {
            return ("FAIL parse", false)
        }
        let unverified = store.save(phrase: parsed.phrase, steps: parsed.steps, verified: false)
        if case .saved = unverified { problems.append("unverified") }
        let first = engine.run(phrase: "focus mode", store: &store, perform: { _ in true }, brain: { parsed.steps })
        if case .brain(let steps) = first, steps == parsed.steps, engine.llmCalls == 1 {} else { problems.append("first") }
        let saved = store.save(phrase: parsed.phrase, steps: parsed.steps, verified: true)
        if case .saved = saved {} else { problems.append("save") }
        let second = engine.run(phrase: "focus mode", store: &store, perform: { _ in true }, brain: { ["should not run"] })
        if case .replayed = second, engine.llmCalls == 1 {} else { problems.append("replay") }
        var failing = LearnEngine()
        let fallback = failing.run(phrase: "focus mode", store: &store, perform: { $0 == "close Slack" }, brain: { ["ask"] })
        if case .fallback = fallback, failing.llmCalls == 1, store.match("focus mode") == nil {} else { problems.append("fallback") }
        _ = store.save(phrase: parsed.phrase, steps: parsed.steps, verified: true)
        let listed = store.items.map(\.phrase)
        let undone = store.undo() && store.items.isEmpty
        if !undone || listed != ["focus mode"] { problems.append("undo") }
        let text = problems.isEmpty ? "PASS phrase=focus mode steps=close Slack | open Notes" : "FAIL \(problems.joined(separator: ", "))"
        return (text, problems.isEmpty)
    }
}
