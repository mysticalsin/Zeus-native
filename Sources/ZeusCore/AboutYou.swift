import Foundation

/// The person's second brain (an Obsidian-style folder of Markdown notes). ZEUS only reads it,
/// except for one profile note it writes after the person confirms.
public enum SecondBrain {
    /// ~/Documents/brain when it exists and looks like a vault.
    public static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidate = home.appendingPathComponent("Documents/brain", isDirectory: true)
        return looksLikeVault(candidate) ? candidate : nil
    }

    /// A folder with an `.obsidian` settings folder, or with Markdown notes near the top.
    public static func looksLikeVault(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian").path) { return true }
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.contains { $0.pathExtension.lowercased() == "md" }
            || items.contains { item in
                ((try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [])
                    .contains { $0.pathExtension.lowercased() == "md" }
            }
    }

    /// What ZEUS can say about a vault without reading note contents.
    public struct Summary: Equatable, Sendable {
        public var notes: Int
        /// Top-level folders, biggest first (at most 6).
        public var folders: [String]
        public var hasInbox: Bool
        /// True when the scan stopped at the cap.
        public var truncated: Bool

        public init(notes: Int, folders: [String], hasInbox: Bool, truncated: Bool) {
            self.notes = notes
            self.folders = folders
            self.hasInbox = hasInbox
            self.truncated = truncated
        }
    }

    /// Counts notes and lists top folders, skipping hidden folders. Stops after `cap` files so a
    /// huge vault stays quick.
    public static func summarize(_ root: URL, cap: Int = 20_000) -> Summary {
        var notes = 0
        var perFolder: [String: Int] = [:]
        var seen = 0
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        let rootDepth = root.standardizedFileURL.pathComponents.count
        while let url = walker?.nextObject() as? URL {
            seen += 1
            if seen > cap { break }
            guard url.pathExtension.lowercased() == "md" else { continue }
            notes += 1
            let parts = url.standardizedFileURL.pathComponents
            if parts.count > rootDepth + 1 { perFolder[parts[rootDepth], default: 0] += 1 }
        }
        let folders = perFolder.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(6).map(\.key)
        return Summary(notes: notes, folders: folders,
                       hasInbox: FileManager.default.fileExists(atPath: root.appendingPathComponent("00_Inbox").path),
                       truncated: seen > cap)
    }
}

/// What the person told ZEUS in "Teach ZEUS about you".
public struct AboutYouProfile: Equatable, Sendable {
    public var name: String
    public var work: String
    public var helpWith: String
    public var notes: String

    public init(name: String = "", work: String = "", helpWith: String = "", notes: String = "") {
        self.name = name
        self.work = work
        self.helpWith = helpWith
        self.notes = notes
    }

    private func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Name is the only required answer.
    public var isComplete: Bool { !clean(name).isEmpty }

    /// The profile note, with front matter so the vault's tools can find it.
    public func markdown(created: Date, vaultSummary: SecondBrain.Summary? = nil, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: created)
        var lines = [
            "---",
            "type: profile",
            "source: zeus",
            "created: \(day)",
            "tags: [zeus, profile]",
            "---",
            "",
            "# About \(clean(name))",
            "",
        ]
        func section(_ title: String, _ body: String) {
            let text = clean(body)
            guard !text.isEmpty else { return }
            lines += ["## \(title)", "", text, ""]
        }
        section("Work", work)
        section("What ZEUS should help with", helpWith)
        section("Notes", notes)
        if let summary = vaultSummary {
            lines += ["## Second brain", "",
                      "- \(summary.notes)\(summary.truncated ? "+" : "") notes"
                        + (summary.folders.isEmpty ? "" : ", mostly in \(summary.folders.prefix(3).joined(separator: ", "))"),
                      ""]
        }
        lines.append("_Written by ZEUS on this Mac. Nothing left the Mac._")
        return lines.joined(separator: "\n") + "\n"
    }
}

/// The single write ZEUS makes to a vault: `<vault>/00_Inbox/from-zeus/zeus-profile-<date>.md`.
public enum ProfileNoteWriter {
    public enum WriteError: LocalizedError, Equatable {
        case outsideVault
        case notAVault

        public var errorDescription: String? {
            switch self {
            case .outsideVault: "ZEUS only writes inside 00_Inbox/from-zeus of your vault."
            case .notAVault: "That folder is not there any more."
            }
        }
    }

    public static func folder(in vault: URL) -> URL {
        vault.appendingPathComponent("00_Inbox", isDirectory: true).appendingPathComponent("from-zeus", isDirectory: true)
    }

    /// A free file name for the day; never an existing note.
    public static func plannedURL(in vault: URL, created: Date, timeZone: TimeZone = .current,
                                  exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let base = "zeus-profile-\(formatter.string(from: created))"
        var candidate = folder(in: vault).appendingPathComponent("\(base).md")
        var counter = 2
        while exists(candidate) {
            candidate = folder(in: vault).appendingPathComponent("\(base)-\(counter).md")
            counter += 1
        }
        return candidate
    }

    /// Writes the note without overwriting anything, and only under the from-zeus folder.
    @discardableResult
    public static func write(_ text: String, to url: URL, vault: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: vault.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WriteError.notAVault
        }
        func allowed() -> Bool {
            guard let relative = VaultPathBoundary.relativePath(of: url, in: vault) else { return false }
            return relative.hasPrefix("00_Inbox/from-zeus/") && url.pathExtension == "md"
        }
        guard allowed() else { throw WriteError.outsideVault }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard allowed() else { throw WriteError.outsideVault }
        // .withoutOverwriting: an existing note is never replaced.
        try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }
}
