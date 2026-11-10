import Foundation

/// Rules and about-me facts the person asked to remember. Never filled from screen OCR.
public struct UserMemoryStore: Codable, Equatable, Sendable {
    public struct Rule: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var text: String
        public var created: Date

        public init(id: UUID = UUID(), text: String, created: Date = Date()) {
            self.id = id
            self.text = text
            self.created = created
        }
    }

    public struct Fact: Codable, Equatable, Identifiable, Sendable {
        public enum Source: String, Codable, Sendable { case you, contacts, mail, learned }

        public var id: UUID
        public var text: String
        public var source: Source
        public var created: Date

        public init(id: UUID = UUID(), text: String, source: Source = .you, created: Date = Date()) {
            self.id = id
            self.text = text
            self.source = source
            self.created = created
        }
    }

    public var rules: [Rule] = []
    public var facts: [Fact] = []

    public init(rules: [Rule] = [], facts: [Fact] = []) {
        self.rules = rules
        self.facts = facts
    }

    public static let ruleLimit = 15

    /// Credit cards, health identifiers, passwords, and similar never get stored.
    public static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("password") || lower.contains("cvv") || lower.contains("social security") { return true }
        if trimmed.range(of: #"\b\d{3}-\d{2}-\d{4}\b"#, options: .regularExpression) != nil { return true }
        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 13 && digits.count <= 19,
           trimmed.range(of: #"\d[\d\s-]{11,}\d"#, options: .regularExpression) != nil { return true }
        return false
    }

    public enum StoreResult: Equatable, Sendable {
        case storedRule(Rule)
        case storedFact(Fact)
        case rejectedSensitive
        case rejectedScreenSource
    }

    public mutating func rememberRule(_ text: String, at date: Date = Date()) -> StoreResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .rejectedSensitive }
        guard !Self.isSensitive(cleaned) else { return .rejectedSensitive }
        let rule = Rule(text: cleaned, created: date)
        rules.insert(rule, at: 0)
        if rules.count > 64 { rules = Array(rules.prefix(64)) }
        return .storedRule(rule)
    }

    public mutating func rememberFact(_ text: String, source: Fact.Source = .you, at date: Date = Date()) -> StoreResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .rejectedSensitive }
        guard !Self.isSensitive(cleaned) else { return .rejectedSensitive }
        let fact = Fact(text: cleaned, source: source, created: date)
        facts.insert(fact, at: 0)
        if facts.count > 128 { facts = Array(facts.prefix(128)) }
        return .storedFact(fact)
    }

    /// Screen text must never become memory.
    public mutating func learnFromScreen(_ text: String) -> StoreResult {
        _ = text
        return .rejectedScreenSource
    }

    /// Words that say nothing about which entry is meant ("forget my dentist" is about "dentist").
    private static let fillerWords: Set<String> = [
        "a", "an", "the", "my", "me", "i", "it", "its", "this", "that", "these", "those", "about", "of", "to", "is", "are",
        "everything", "anything", "all", "and", "or", "you", "your", "mine", "our", "we",
    ]

    /// Normalised words (case, accents, `'s` folded as in `Utterance`), for whole-word matching.
    static func matchWords(_ text: String) -> [String] {
        Utterance(text).words
    }

    /// Removes the entries the phrase names and returns how many went. An entry matches when the
    /// phrase's words, minus filler at both ends, appear in it as whole words in the same order
    /// ("tea" never matches "teacher"; "I'm vegan" matches "I'm vegan"). A phrase that is only
    /// filler removes nothing.
    public mutating func forget(matching phrase: String) -> Int {
        let found = matchingEntries(phrase)
        guard !found.isEmpty else { return 0 }
        let ids = Set(found.map(\.id))
        rules.removeAll { ids.contains($0.id) }
        facts.removeAll { ids.contains($0.id) }
        return found.count
    }

    /// What `forget(matching:)` would remove, without removing anything.
    public func matchingEntries(_ phrase: String) -> [(id: UUID, text: String)] {
        var needle = Self.matchWords(phrase)
        while let first = needle.first, Self.fillerWords.contains(first) { needle.removeFirst() }
        while let last = needle.last, Self.fillerWords.contains(last) { needle.removeLast() }
        guard !needle.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            let words = Self.matchWords(text)
            guard words.count >= needle.count else { return false }
            return (0...(words.count - needle.count)).contains { start in
                Array(words[start..<(start + needle.count)]) == needle
            }
        }
        return rules.filter { matches($0.text) }.map { ($0.id, $0.text) }
            + facts.filter { matches($0.text) }.map { ($0.id, $0.text) }
    }

    public enum ForgetOutcome: Equatable, Sendable {
        case removed(Int)
        /// More than one entry matches; nothing was removed. The person must say which one.
        case needsChoice([String])
    }

    /// Removes the single entry a phrase names. Several matches are never deleted silently: they are
    /// returned for the person to choose from, unless exactly one equals the phrase word for word.
    public mutating func forgetOne(matching phrase: String) -> ForgetOutcome {
        let found = matchingEntries(phrase)
        switch found.count {
        case 0: return .removed(0)
        case 1: return .removed(forget(matching: phrase))
        default:
            let wanted = Self.matchWords(phrase)
            let exact = found.filter { Self.matchWords($0.text) == wanted }
            if exact.count == 1 {
                let id = exact[0].id
                rules.removeAll { $0.id == id }
                facts.removeAll { $0.id == id }
                return .removed(1)
            }
            return .needsChoice(found.map(\.text))
        }
    }

    /// "Forget that": drops the most recently added rule or fact. Returns how many went (0 or 1).
    public mutating func forgetNewest() -> Int {
        let rule = rules.max { $0.created < $1.created }
        let fact = facts.max { $0.created < $1.created }
        switch (rule, fact) {
        case (nil, nil): return 0
        case (let rule?, let fact?) where fact.created > rule.created:
            facts.removeAll { $0.id == fact.id }
        case (let rule?, _):
            rules.removeAll { $0.id == rule.id }
        case (nil, let fact?):
            facts.removeAll { $0.id == fact.id }
        }
        return 1
    }

    public func relevantRules(for query: String, limit: Int = ruleLimit) -> [Rule] {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !words.isEmpty else { return Array(rules.prefix(limit)) }
        let scored = rules.map { rule -> (Rule, Int) in
            let ruleWords = Set(rule.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (rule, ruleWords.intersection(words).count)
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.created > $1.0.created : $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    public func promptBlock(for query: String) -> String {
        let picked = relevantRules(for: query)
        var lines: [String] = []
        for rule in picked { lines.append("- \(rule.text)") }
        for fact in facts.prefix(8) { lines.append("- \(fact.text)") }
        guard !lines.isEmpty else { return "" }
        return "About this person:\n" + lines.joined(separator: "\n")
    }

    public func affectsAnswer(query: String, answerWithout: String, answerWith: String) -> Bool {
        answerWithout != answerWith || !relevantRules(for: query).isEmpty
    }
}

public enum UserMemoryCommands: Sendable {
    public struct Parsed: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case remember(String), forget(String) }
        public var kind: Kind
    }

    /// "forget that" alone is the bare command (the newest entry) and parses as `.forget("that")`.
    /// "forget that I'm vegan" and "forget I'm vegan" name what to forget. Remembered text keeps
    /// the casing and possessives as said.
    public static func parse(_ text: String) -> Parsed? {
        var utterance = Utterance(text)
        utterance.stripFiller()
        let words = utterance.words
        guard let first = words.first else { return nil }
        func rest(from index: Int) -> String {
            index < words.count ? utterance.source(index..<words.count).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        if first == "forget" {
            if words.count == 1 || (words.count == 2 && words[1] == "that") {
                return Parsed(kind: .forget("that"))
            }
            var skip = 1
            if words[skip] == "that" { skip += 1 }
            if skip < words.count, words[skip] == "about" { skip += 1 }
            let named = rest(from: skip)
            return named.isEmpty ? Parsed(kind: .forget("that")) : Parsed(kind: .forget(named))
        }
        if first == "remember", words.count > 1 {
            var skip = 1
            if (words[1] == "that" || words[1] == "rule"), words.count > 2 { skip = 2 }
            let text = rest(from: skip)
            return text.isEmpty ? nil : Parsed(kind: .remember(text))
        }
        return nil
    }
}

/// Why the memory file couldn't be used. The file is left exactly as it was.
public enum UserMemoryError: Error, Equatable, LocalizedError, Sendable {
    /// The file exists but can't be read.
    case unreadable(String)
    /// The file exists but isn't a memory file this build understands (damaged, or from a newer build).
    case undecodable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "The memory file couldn't be read: \(detail)"
        case .undecodable(let detail): "The memory file isn't in a form this version understands: \(detail)"
        }
    }
}

/// JSON persistence for rules and facts in Application Support.
public struct UserMemoryPersistence: Sendable {
    public static let shared = UserMemoryPersistence(url: ZeusPaths.supportDirectory.appendingPathComponent("user-memory.json"))

    public let url: URL

    public init(url: URL) { self.url = url }

    /// Where an unusable file is kept, untouched, for recovery.
    public var corruptCopyURL: URL { url.appendingPathExtension("corrupt") }

    /// The store, or an empty one when the file is missing or unusable. An unusable file is left
    /// in place and `save` refuses to replace it; use `loadChecked()` to see why.
    public func load() -> UserMemoryStore {
        (try? loadChecked()) ?? UserMemoryStore()
    }

    /// An empty store only when there is no file. A file (including a zero-byte one) that can't be read or
    /// decoded throws, is never modified, and is copied once to `corruptCopyURL`.
    public func loadChecked() throws -> UserMemoryStore {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return UserMemoryStore() }
        harden()
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw UserMemoryError.unreadable(error.localizedDescription) }
        func preserve() {
            if !fm.fileExists(atPath: corruptCopyURL.path) {
                _ = fm.createFile(atPath: corruptCopyURL.path, contents: data, attributes: [.posixPermissions: 0o600])
            }
        }
        // A zero-byte file is a truncated one, not an empty memory: keep it and refuse to replace it.
        guard !data.isEmpty else {
            preserve()
            throw UserMemoryError.undecodable("the file is empty (truncated)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(UserMemoryStore.self, from: data)
        } catch {
            preserve()
            throw UserMemoryError.undecodable(String(describing: error).prefix(160).description)
        }
    }

    /// Writes the store, 0600 inside a 0700 folder, replacing the file atomically. Refuses (throws
    /// the load error) when the existing file can't be read or decoded, so a damaged or newer-format
    /// file is never overwritten by a store that was built without it.
    public func save(_ store: UserMemoryStore) throws {
        _ = try loadChecked()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store)
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        harden()
        // A private temp file in the same folder, renamed over the target: never readable by others, even briefly.
        let temp = directory.appendingPathComponent(".user-memory-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temp.path, url.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Moves an unusable file aside (kept as a `.corrupt` copy) so a fresh memory can start.
    /// Only for an explicit "start over"; nothing calls this on its own.
    public func quarantine() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        var target = corruptCopyURL
        if fm.fileExists(atPath: target.path) {
            target = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
        }
        try fm.moveItem(at: url, to: target)
    }

    /// Repairs permissive modes left by an older build: folder 0700, file 0600 (best effort, own files only).
    private func harden() {
        let fm = FileManager.default
        let owner = NSNumber(value: getuid())
        for (path, mode) in [(url.deletingLastPathComponent().path, 0o700), (url.path, 0o600)] {
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  (attributes[.ownerAccountID] as? NSNumber) == owner,
                  let current = attributes[.posixPermissions] as? NSNumber, current.intValue & 0o777 != mode else { continue }
            try? fm.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        }
    }
}
