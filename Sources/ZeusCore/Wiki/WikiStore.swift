import Foundation

/// Settings that live beside the pages: the "learning paused" flag and the meetings the person forgot.
/// A forgotten meeting is never ingested again.
public struct WikiStoreState: Codable, Equatable, Sendable {
    public var learningPaused: Bool
    public var forgottenMeetings: [UUID]
    /// Durable "a reset started and has not finished" marker. While it is set, learning stays paused and the
    /// reset is reported as unfinished, whatever else on disk looks healthy.
    public var resetInProgress: Bool

    public init(learningPaused: Bool = false, forgottenMeetings: [UUID] = [], resetInProgress: Bool = false) {
        self.learningPaused = learningPaused
        self.forgottenMeetings = forgottenMeetings
        self.resetInProgress = resetInProgress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        learningPaused = try container.decodeIfPresent(Bool.self, forKey: .learningPaused) ?? false
        forgottenMeetings = try container.decodeIfPresent([UUID].self, forKey: .forgottenMeetings) ?? []
        resetInProgress = try container.decodeIfPresent(Bool.self, forKey: .resetInProgress) ?? false
    }
}

public enum WikiStoreError: LocalizedError, Equatable {
    case invalidID(String)
    case unpromotedGlobal(String)
    case write(String)
    case state(String)

    public var errorDescription: String? {
        switch self {
        case .invalidID(let id): return "“\(id)” is not a valid page id."
        case .unpromotedGlobal(let title): return "“\(title)” is marked global without a promotion record, so it was not saved."
        case .write(let detail): return detail
        case .state(let detail): return detail
        }
    }
}

/// Page writes and deletes that failed, kept as explicit intents (save THIS page value, delete THIS id) until
/// their commit succeeds. Later compilations stage on top of them and never drop or overwrite one: a newer
/// staged value for the same page replaces an older value only because it was built from it. Held in memory.
public struct WikiPendingWrites: Sendable, Equatable {
    public enum Intent: Sendable, Equatable {
        case save(WikiPage)
        case delete
    }

    public private(set) var intents: [String: Intent] = [:]

    public init() {}

    public var isEmpty: Bool { intents.isEmpty }

    public func intent(for id: String) -> Intent? { intents[id] }

    /// Records the difference between `old` (the effective list) and `new` as intents and returns the new
    /// effective list. A page with a pending delete is never brought back by `new`.
    public mutating func stage(replacing old: [WikiPage], with new: [WikiPage]) -> [WikiPage] {
        var current: [String: WikiPage] = [:]
        for page in old where current[page.id] == nil { current[page.id] = page }
        var seen = Set<String>()
        var desired: [WikiPage] = []
        for page in new where seen.insert(page.id).inserted {
            if intents[page.id] == .delete { continue }
            desired.append(page)
            if current[page.id] != page { intents[page.id] = .save(page) }
        }
        for id in current.keys where !seen.contains(id) { intents[id] = .delete }
        return desired
    }

    /// Pages as loaded from disk, with the pending intents applied on top.
    public func overlaying(_ loaded: [WikiPage]) -> [WikiPage] {
        var result: [WikiPage] = []
        var placed = Set<String>()
        for page in loaded {
            switch intents[page.id] {
            case .delete?: continue
            case .save(let value)?:
                if placed.insert(page.id).inserted { result.append(value) }
            case nil:
                if placed.insert(page.id).inserted { result.append(page) }
            }
        }
        for (id, intent) in intents.sorted(by: { $0.key < $1.key }) {
            if case .save(let value) = intent, placed.insert(id).inserted { result.append(value) }
        }
        return result
    }

    /// A direct save of this page succeeded and supersedes whatever was pending for it.
    public mutating func noteSaved(_ id: String) {
        intents[id] = nil
    }

    /// A direct change (an edit, a pin, a promotion) is staged as a save intent first, then committed. When the
    /// commit fails the intent stays, so the caller keeps showing `page` as the effective value and every later
    /// `retry` writes it. Returns the failure message, or nil once the page is on disk. A page with a pending
    /// delete is not brought back.
    public mutating func commit(_ page: WikiPage, using store: WikiStore) -> String? {
        guard intents[page.id] != .delete else { return nil }
        intents[page.id] = .save(page)
        do {
            try store.save(page)
            intents[page.id] = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Attempts every intent. An intent is cleared only when its commit succeeded. Returns one message per failure.
    public mutating func retry(using store: WikiStore) -> [String] {
        var failures: [String] = []
        for id in intents.keys.sorted() {
            guard let intent = intents[id] else { continue }
            do {
                switch intent {
                case .save(let page): try store.save(page)
                case .delete: try store.delete(id: id)
                }
                intents[id] = nil
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return failures
    }
}

/// One JSON file per page under `root`, written 0600 into a 0700 directory. Writes are atomic: a temporary
/// file is created with its final permissions and swapped in, so a crash never leaves half a page.
/// Every failure is thrown or listed; nothing is skipped silently.
public struct WikiStore: Sendable {
    public struct LoadResult: Sendable {
        public var pages: [WikiPage]
        /// One line per file that could not be read, or that was changed on load.
        public var failures: [String]
    }

    public static let stateFileName = "_state.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var standard: WikiStore {
        WikiStore(root: ZeusPaths.supportDirectory.appendingPathComponent("wiki", isDirectory: true))
    }

    public var stateURL: URL { root.appendingPathComponent(Self.stateFileName) }

    /// ASCII letters, digits, `-`, `_` and `.`, starting with a letter or digit: never a path.
    public static func isValidID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, id.utf8.count <= 120 else { return false }
        func alnum(_ scalar: Unicode.Scalar) -> Bool {
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        guard alnum(first) else { return false }
        return id.unicodeScalars.allSatisfy { alnum($0) || $0 == "-" || $0 == "_" || $0 == "." }
    }

    private func fileURL(for id: String) -> URL {
        root.appendingPathComponent("\(id).json")
    }

    // MARK: Pages

    public func loadPages() -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return LoadResult(pages: [], failures: []) }
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            return LoadResult(pages: [], failures: ["Couldn't read the Memory folder: \(error.localizedDescription)"])
        }
        var pages: [WikiPage] = []
        var failures: [String] = []
        for file in files where file.pathExtension == "json" {
            let name = file.lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") { continue }
            do {
                let data = try Data(contentsOf: file)
                var page = try Self.decoder().decode(WikiPage.self, from: data)
                guard "\(page.id).json" == name else {
                    failures.append("\(name): the page id “\(page.id)” doesn't match the file name.")
                    continue
                }
                if page.scope == .global, page.promotedBy?.isEmpty != false || page.promotedAt == nil {
                    page = WikiPromotion.demote(page)
                    failures.append("\(name): marked global without a promotion record, so it is shown as personal.")
                } else if page.scope == .global, page.needsReview {
                    page = WikiPromotion.demote(page)
                    failures.append("\(name): needs review, so it is shown as personal.")
                }
                pages.append(page)
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        pages.sort { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        return LoadResult(pages: pages, failures: failures.sorted())
    }

    public func save(_ page: WikiPage) throws {
        guard Self.isValidID(page.id) else { throw WikiStoreError.invalidID(page.id) }
        if page.scope == .global {
            guard let by = page.promotedBy, !by.isEmpty, page.promotedAt != nil else {
                throw WikiStoreError.unpromotedGlobal(page.title)
            }
        }
        let data: Data
        do {
            data = try Self.encoder().encode(page)
        } catch {
            throw WikiStoreError.write("Couldn't encode “\(page.title)”: \(error.localizedDescription)")
        }
        try write(data, to: fileURL(for: page.id), what: "“\(page.title)”")
    }

    /// Removes a page's file. A page that has no file is already gone.
    public func delete(id: String) throws {
        guard Self.isValidID(id) else { throw WikiStoreError.invalidID(id) }
        let target = fileURL(for: id)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: target.path) else { return }
        do {
            try fileManager.removeItem(at: target)
        } catch {
            throw WikiStoreError.write("Couldn't delete the page file \(target.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: State

    /// A missing file is the default state. An unreadable one throws: callers treat that as "paused".
    public func loadState() throws -> WikiStoreState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return WikiStoreState() }
        do {
            return try Self.decoder().decode(WikiStoreState.self, from: Data(contentsOf: stateURL))
        } catch {
            throw WikiStoreError.state("Couldn't read \(stateURL.path): \(error.localizedDescription)")
        }
    }

    /// `loadState`, but an unreadable file doesn't hide the forgotten meetings. The result is then fail-closed
    /// (`learningPaused` true), `error` says what went wrong, and `forgottenMeetings` holds every id that can
    /// still be read out of the settings file (none when it isn't even JSON) plus every id in the forget
    /// journal, which is kept apart from the settings. An unreadable journal line also pauses learning.
    /// Deleting and forgetting keep working on those ids; only a confirmed `resetState` makes learning run again.
    public func loadStateRecovering() -> (state: WikiStoreState, error: String?) {
        let journal = loadJournal()
        var state: WikiStoreState
        var messages: [String] = []
        do {
            state = try loadState()
        } catch {
            messages.append(error.localizedDescription)
            let object = (try? Data(contentsOf: stateURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let ids = (object?["forgottenMeetings"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap(UUID.init(uuidString:)) }
            state = WikiStoreState(learningPaused: true, forgottenMeetings: ids)
        }
        if let problem = journal.error {
            messages.append(problem)
            state.learningPaused = true
        }
        if state.resetInProgress {
            messages.append("A reset of Memory's settings didn't finish, so learning stays paused until a reset completes.")
            state.learningPaused = true
        }
        for id in journal.ids where !state.forgottenMeetings.contains(id) { state.forgottenMeetings.append(id) }
        return (state, messages.isEmpty ? nil : messages.joined(separator: " "))
    }

    /// Replaces unreadable settings with a default state (learning not paused), without ever leaving a moment
    /// in which no authoritative file exists: the unreadable files are first COPIED to
    /// `_state.corrupt-<time>.json` / `_forgotten.corrupt-<time>.log`, the forget journal is rewritten cleanly
    /// with every id that can be read plus `forgetting`, and only then is the settings file atomically replaced.
    /// If any step fails (or the process exits), the original unreadable file is still there, so the next
    /// launch is still paused with the error shown, until a reset succeeds.
    @discardableResult
    public func resetState(forgetting extra: [UUID] = [], now: Date = Date()) throws -> WikiStoreState {
        let fileManager = FileManager.default
        var ids = loadStateRecovering().state.forgottenMeetings
        for id in extra where !ids.contains(id) { ids.append(id) }
        let stamp = Int(now.timeIntervalSince1970)
        do {
            if fileManager.fileExists(atPath: stateURL.path) {
                try keepCopy(of: stateURL, as: "_state.corrupt-\(stamp).json")
            }
            if fileManager.fileExists(atPath: journalURL.path) {
                try keepCopy(of: journalURL, as: "_forgotten.corrupt-\(stamp).log")
            }
        } catch {
            throw WikiStoreError.state("Couldn't keep a copy of the unreadable settings, so they were not reset: \(error.localizedDescription)")
        }
        // 1. The new durable state first: paused, marked unfinished, holding every known id. From here on a
        //    failure or exit leaves a readable record that learning is paused and why.
        try saveState(WikiStoreState(learningPaused: true, forgottenMeetings: ids, resetInProgress: true))
        // 2. Only then repair the journal (the backup copy above keeps the old one).
        try write(Data(Self.journalText(ids).utf8), to: journalURL, what: "the list of forgotten meetings")
        // 3. Commit: the final state clears the marker. Until this write succeeds the marker stays.
        let state = WikiStoreState(learningPaused: false, forgottenMeetings: ids, resetInProgress: false)
        try saveState(state)
        return state
    }

    private func keepCopy(of source: URL, as name: String) throws {
        let fileManager = FileManager.default
        let backup = root.appendingPathComponent(name)
        try? fileManager.removeItem(at: backup)
        try fileManager.copyItem(at: source, to: backup)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    }

    // MARK: Forget journal

    /// Append-only tombstone list, one UUID per line, separate from the settings so that a corrupt or reset
    /// settings file can never lose a forget.
    public var journalURL: URL { root.appendingPathComponent(Self.journalFileName) }

    public static let journalFileName = "_forgotten.log"

    private static func journalText(_ ids: [UUID]) -> String {
        ids.map { $0.uuidString + "\n" }.joined()
    }

    /// Every id readable from the journal. `error` is set when the file can't be read or has lines that
    /// aren't ids (for example a torn last line); the readable ids are still returned.
    public func loadJournal() -> (ids: [UUID], error: String?) {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return ([], nil) }
        let data: Data
        do {
            data = try Data(contentsOf: journalURL)
        } catch {
            return ([], "Couldn't read the list of forgotten meetings: \(error.localizedDescription)")
        }
        var ids: [UUID] = []
        var bad = 0
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            if let id = UUID(uuidString: text) {
                if !ids.contains(id) { ids.append(id) }
            } else {
                bad += 1
            }
        }
        let error = bad > 0 ? "The list of forgotten meetings has \(bad) unreadable line(s)." : nil
        return (ids, error)
    }

    /// Durably appends ids to the journal (flushed to disk) before returning. Throws when that fails.
    private func appendJournal(_ ids: [UUID]) throws {
        let known = Set(loadJournal().ids)
        let fresh = ids.filter { !known.contains($0) }
        guard !fresh.isEmpty else { return }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if !fileManager.fileExists(atPath: journalURL.path) {
                guard fileManager.createFile(atPath: journalURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw WikiStoreError.state("Couldn't create the list of forgotten meetings.")
                }
            }
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            // The leading newline keeps a torn previous line from swallowing this id.
            try handle.write(contentsOf: Data(("\n" + Self.journalText(fresh)).utf8))
            try handle.synchronize()
        } catch let error as WikiStoreError {
            throw error
        } catch {
            throw WikiStoreError.state("Couldn't record the forgotten meeting: \(error.localizedDescription)")
        }
    }

    public func saveState(_ state: WikiStoreState) throws {
        let data: Data
        do {
            data = try Self.encoder().encode(state)
        } catch {
            throw WikiStoreError.state("Couldn't encode the Memory settings: \(error.localizedDescription)")
        }
        try write(data, to: stateURL, what: "the Memory settings")
    }

    @discardableResult
    public func setLearningPaused(_ paused: Bool) throws -> WikiStoreState {
        var state = try loadState()
        if !paused, state.resetInProgress {
            throw WikiStoreError.state("A reset of Memory's settings didn't finish, so learning can't resume yet.")
        }
        state.learningPaused = paused
        try saveState(state)
        return state
    }

    /// Remembers that these meetings were forgotten, so they are never learned from again. The journal write
    /// is the commitment: it is flushed before this returns, works even while the settings are unreadable, and
    /// throws when it failed (the caller must then not acknowledge the forget). The settings copy is best effort.
    /// Returns the merged state (settings plus journal).
    @discardableResult
    public func forget(meetings ids: [UUID]) throws -> WikiStoreState {
        try appendJournal(ids)
        if var state = try? loadState() {
            let before = state.forgottenMeetings
            for id in ids where !state.forgottenMeetings.contains(id) { state.forgottenMeetings.append(id) }
            if state.forgottenMeetings != before { try? saveState(state) }
        }
        return loadStateRecovering().state
    }

    // MARK: Writing

    private func write(_ data: Data, to target: URL, what: String) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let temporary = root.appendingPathComponent(".\(UUID().uuidString).tmp")
            guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw WikiStoreError.write("Couldn't create \(temporary.lastPathComponent).")
            }
            do {
                if fileManager.fileExists(atPath: target.path) {
                    _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: target)
                }
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } catch let error as WikiStoreError {
            throw error
        } catch {
            throw WikiStoreError.write("Couldn't save \(what): \(error.localizedDescription)")
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
