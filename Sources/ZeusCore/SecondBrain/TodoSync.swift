import Foundation

/// The to-do list on disk plus its optional two-way link to a Markdown note.
/// ZEUS keeps its own copy (todos.json) and, when the connection is read-write, mirrors it into
/// the chosen note. Edits made in the note (Obsidian, Logseq, any editor) are picked up on `pull`.
/// It never writes anywhere `BrainConnection.mayWrite` refuses.
public struct TodoSync: Sendable {
    public var list: TodoList
    public var connection: BrainConnection?
    public let storeFile: URL
    public private(set) var lastSync: Date?
    /// Set when todos.json could not be read at launch: where the unreadable file went, or why it stayed.
    public private(set) var loadNotice: String?
    /// The last time ZEUS's own copy could not be written; cleared by the next good save.
    public private(set) var saveError: String?
    /// Why the connected note could not be read or ZEUS's copy could not be saved during `pull`; cleared by the next good pass.
    public private(set) var syncError: String?
    /// True after a `pull` changed the list but the save failed: the next `pull` (or `noteMayHaveChanged`) retries it.
    public private(set) var pendingSave = false
    private var noteStamp: Date?
    private var noteURLCache: String?
    /// True when an unreadable file could not be moved aside: saving would overwrite it, so nothing is saved.
    private var storeLocked = false

    public init(storeFile: URL, connection: BrainConnection? = nil) {
        self.storeFile = storeFile
        self.connection = connection
        let loaded = Self.loadStore(at: storeFile)
        list = loaded.list
        loadNotice = loaded.notice
        storeLocked = loaded.locked
    }

    /// Reads the saved list. A missing file is a fresh start; a file that exists but does not decode
    /// is moved aside (never overwritten) so the next save cannot destroy what is still on disk.
    static func loadStore(at file: URL, now: Date = Date()) -> (list: TodoList, notice: String?, locked: Bool) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return (TodoList(), nil, false) }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(TodoList.self, from: data) {
            return (saved, nil, false)
        }
        let stamp = Int(now.timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(4).lowercased()
        let aside = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.deletingPathExtension().lastPathComponent).corrupt-\(stamp)-\(suffix).\(file.pathExtension)")
        do {
            try manager.moveItem(at: file, to: aside)
            return (TodoList(), "Your to-do file could not be read. It was kept as \(aside.lastPathComponent) next to it, and a new list was started.", false)
        } catch {
            return (TodoList(), "Your to-do file could not be read and could not be moved aside, so ZEUS will not save to-dos until it is fixed or removed.", true)
        }
    }

    /// The note this list mirrors today, if any. Nil for read-only or unconnected brains.
    public func noteURL(on date: Date = Date()) -> URL? {
        guard let connection, connection.access == .readWrite, let url = connection.todoURL(on: date),
              connection.mayWrite(url, on: date) else { return nil }
        return url
    }

    /// A cheap, non-mutating check: whether `pull` would read the note. Lets a timer skip the
    /// mutating call (which would notify observers) on every tick where nothing changed.
    public func noteMayHaveChanged(now: Date = Date()) -> Bool {
        if pendingSave { return true }
        guard let url = noteURL(on: now) else { return false }
        if noteURLCache != url.path { return true }
        guard let stamp = Self.modified(url) else { return false }
        return stamp != noteStamp
    }

    /// Reads the note if it changed since we last saw it and adopts its tasks. True if the list changed.
    @discardableResult
    public mutating func pull(now: Date = Date()) -> Bool {
        if pendingSave {
            pendingSave = (try? saveStore()) == nil
        }
        guard let url = noteURL(on: now) else { return false }
        if noteURLCache != url.path { noteURLCache = url.path; noteStamp = nil }
        guard let stamp = Self.modified(url), stamp != noteStamp else { return false }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // The stamp stays unseen so the next tick retries; the list is left as it is.
            syncError = "The note \(url.lastPathComponent) could not be read: \(error.localizedDescription)"
            return false
        }
        syncError = nil
        noteStamp = stamp
        let before = list
        list.adopt(TodoMarkdown.items(in: text))
        lastSync = now
        guard list != before else { return false }
        do { try saveStore() } catch { pendingSave = true }
        return true
    }

    /// Saves ZEUS's copy and, when allowed, writes the tasks into the note (only task lines change).
    /// A note that exists but cannot be read is never treated as empty: this throws and leaves it alone.
    public mutating func commit(now: Date = Date()) throws {
        try saveStore()
        pendingSave = false
        guard let url = noteURL(on: now) else { return }
        let existing: String
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                existing = try String(contentsOf: url, encoding: .utf8)
            } catch {
                syncError = "The note \(url.lastPathComponent) could not be read, so ZEUS left it unchanged: \(error.localizedDescription)"
                throw error
            }
        } else {
            existing = ""
        }
        syncError = nil
        let updated = TodoMarkdown.apply(list.items, to: existing)
        if updated != existing {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
        noteURLCache = url.path
        noteStamp = Self.modified(url)
        lastSync = now
    }

    /// Writes ZEUS's copy atomically. Throws (and records `saveError`) instead of failing silently.
    private mutating func saveStore() throws {
        if storeLocked {
            saveError = "ZEUS will not save to-dos until the unreadable to-do file is fixed or removed."
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let data = try JSONEncoder().encode(list)
            try FileManager.default.createDirectory(at: storeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storeFile, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Your to-dos could not be saved: \(error.localizedDescription)"
            throw error
        }
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Repairs a saved tab row that an earlier launch left behind: it saved every one-time migration flag
/// without saving the upgraded row, so no migration condition is true any more. Versioned (the app stores
/// `version` once it has run) and idempotent. Kept here so ZeusCore tests can reach it.
public enum TopBarLayoutRepair {
    public static let version = 1
    /// The tabs the one-time row upgrades switch on.
    public static let upgradeTabs: [TopBarTab] = [.teleprompter, .insomnia, .polyglot, .recordly, .scribe]

    /// Adds each upgrade tab the row lacks and the person never had the chance to turn off (it is not in
    /// the `known` list saved with the row), then puts the default row in front. Tabs they removed
    /// while the build knew them stay off.
    public static func repaired(_ layout: TopBarLayout, savedKnown: String?) -> TopBarLayout {
        let knownRaw = savedKnown?.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let known = Set(knownRaw)
        let missing = upgradeTabs.filter { !layout.contains($0) && !known.contains($0.rawValue) }
        guard !missing.isEmpty else { return layout }
        return TopBarLayout(tabs: layout.tabs + missing).defaultRowOrdered()
    }
}
