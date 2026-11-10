import Foundation

/// Quick capture into the explicitly selected second brain's inbox. Always a new Markdown note.
public enum BrainCapture {
    public enum WriteError: LocalizedError, Equatable {
        case unavailableDestination

        public var errorDescription: String? {
            "The selected vault inbox is unavailable or read-only. Check Settings › Memory."
        }
    }

    /// A configured Memory connection always wins, including its read-only setting. A legacy
    /// Teach ZEUS About You choice may be used only when no Memory connection was supplied.
    /// Never discovers a different vault when an explicitly chosen one is missing.
    public static func connection(configured: BrainConnection?, legacyVault: URL?) -> BrainConnection? {
        if let configured { return configured }
        guard let legacyVault else { return nil }
        return BrainConnection(source: BrainSource(kind: .markdown, name: legacyVault.lastPathComponent,
                                                   path: legacyVault.path),
                               access: .readWrite, inboxFolder: "00_Inbox/from-zeus")
    }

    /// "zeus-2026-10-31-groceries-for-the-weekend.md"-style slug: lowercase ASCII words, max 6.
    public static func slug(_ title: String) -> String {
        let folded = title.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.prefix(6)
        let joined = words.joined(separator: "-")
        return joined.isEmpty ? "note" : String(joined.prefix(60))
    }

    public static func plannedURL(in vault: URL, title: String, created: Date, timeZone: TimeZone = .current,
                                  exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        plannedURL(folder: ProfileNoteWriter.folder(in: vault), title: title, created: created, timeZone: timeZone, exists: exists)
    }

    public static func plannedURL(connection: BrainConnection, title: String, created: Date, timeZone: TimeZone = .current,
                                  exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL? {
        guard connection.access == .readWrite, connection.source.kind.isFileBased,
              let folder = BrainConnection.inside(connection.source.url, connection.inboxFolder) else { return nil }
        let target = plannedURL(folder: folder, title: title, created: created, timeZone: timeZone, exists: exists)
        return connection.mayWrite(target) ? target : nil
    }

    private static func plannedURL(folder: URL, title: String, created: Date, timeZone: TimeZone,
                                   exists: (URL) -> Bool) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let base = "zeus-\(formatter.string(from: created))-\(slug(title))"
        var candidate = folder.appendingPathComponent("\(base).md")
        var counter = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    /// Only the previewed new note, only in this connection's inbox. Existing notes, including
    /// a name claimed after the preview was shown, are never replaced.
    @discardableResult
    public static func write(_ text: String, to target: URL, connection: BrainConnection) throws -> URL {
        func allowed() -> Bool {
            guard connection.mayWrite(target), target.pathExtension == "md",
                  let inbox = BrainConnection.inside(connection.source.url, connection.inboxFolder),
                  VaultPathBoundary.relativePath(of: target, in: inbox) != nil else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: connection.source.url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard allowed() else { throw WriteError.unavailableDestination }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard allowed() else { throw WriteError.unavailableDestination }
        try Data(text.utf8).write(to: target, options: .withoutOverwriting)
        return target
    }

    /// The note: front matter (type, source, created), a title and the body as written.
    public static func note(title: String, body: String, source: String, created: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let safeSource = source.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return [
            "---",
            "type: capture",
            "source: zeus-\(safeSource.isEmpty ? "app" : safeSource)",
            "created: \(formatter.string(from: created))",
            "tags: [zeus, inbox]",
            "---",
            "",
            "# \(cleanTitle.isEmpty ? "Note from ZEUS" : cleanTitle)",
            "",
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
        ].joined(separator: "\n")
    }

    /// The explicitly chosen legacy vault only. Kept for older callers; an unavailable choice
    /// must not redirect a write to another folder merely because it resembles a vault.
    public static func vault(saved: URL?, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        _ = home
        if let saved, SecondBrain.looksLikeVault(saved) { return saved }
        return nil
    }
}
