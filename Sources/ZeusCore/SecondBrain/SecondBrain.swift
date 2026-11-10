import Foundation

/// A notes app or folder found on this Mac that ZEUS can connect to.
public struct BrainSource: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case obsidian, logseq, notion, markdown, bear, appleNotes

        public var title: String {
            switch self {
            case .obsidian: "Obsidian vault"
            case .logseq: "Logseq graph"
            case .notion: "Notion export"
            case .markdown: "Markdown folder"
            case .bear: "Bear"
            case .appleNotes: "Apple Notes"
            }
        }

        public var symbol: String {
            switch self {
            case .obsidian: "diamond.fill"
            case .logseq: "circle.hexagongrid.fill"
            case .notion: "square.stack.3d.up.fill"
            case .markdown: "folder.fill"
            case .bear: "pawprint.fill"
            case .appleNotes: "note.text"
            }
        }

        /// Notes are plain files ZEUS can read, search and (if allowed) write to.
        public var isFileBased: Bool { self != .bear && self != .appleNotes }
    }

    public var kind: Kind
    public var name: String
    public var path: String
    public var id: String { kind.rawValue + ":" + path }

    public init(kind: Kind, name: String, path: String) {
        self.kind = kind
        self.name = name
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// What ZEUS may do with a connected source. Writes only ever go to the ZEUS inbox folder
/// or the chosen to-do note, never into other notes.
public struct BrainConnection: Codable, Equatable, Identifiable, Sendable {
    public enum Access: String, Codable, Sendable { case readOnly, readWrite }
    public enum TodoTarget: Codable, Equatable, Sendable {
        /// A note path relative to the vault, e.g. "ZEUS/To-do.md".
        case note(String)
        /// Today's daily note (Obsidian's daily notes folder and format).
        case dailyNote
        /// This source isn't used for to-dos.
        case none
    }

    public var source: BrainSource
    public var access: Access
    public var todo: TodoTarget
    public var inboxFolder: String
    public var id: String { source.id }

    public init(source: BrainSource, access: Access = .readOnly, todo: TodoTarget = .none, inboxFolder: String = "ZEUS/Inbox") {
        self.source = source
        self.access = access
        self.todo = todo
        self.inboxFolder = inboxFolder
    }

    public static let defaultTodoNote = "ZEUS/To-do.md"

    /// The to-do note's file for a date (daily notes change every day).
    public func todoURL(on date: Date = Date(), daily: DailyNoteConfig? = nil) -> URL? {
        guard source.kind.isFileBased else { return nil }
        switch todo {
        case .none: return nil
        case .note(let relative): return Self.inside(source.url, relative)
        case .dailyNote:
            let config = daily ?? DailyNoteConfig.read(vault: source.url)
            return Self.inside(source.url, config.relativePath(for: date))
        }
    }

    /// ZEUS may write this file: read-write access, and it is the to-do note or inside the inbox.
    public func mayWrite(_ url: URL, on date: Date = Date(), daily: DailyNoteConfig? = nil) -> Bool {
        guard access == .readWrite, source.kind.isFileBased,
              VaultPathBoundary.relativePath(of: url, in: source.url) != nil else { return false }
        let target = url.standardizedFileURL.path
        if let todo = todoURL(on: date, daily: daily), todo.standardizedFileURL.path == target { return true }
        // Research reports (ZEUS/Research/<date> <title>.md): new notes only, same rule as the inbox.
        if let research = Self.inside(source.url, ResearchReport.vaultFolder),
           target.hasPrefix(research.standardizedFileURL.path + "/") { return true }
        guard let inbox = Self.inside(source.url, inboxFolder) else { return false }
        return target.hasPrefix(inbox.standardizedFileURL.path + "/")
    }

    /// Joins a relative path onto the vault and refuses anything that escapes it.
    static func inside(_ root: URL, _ relative: String) -> URL? {
        guard !relative.isEmpty, !relative.hasPrefix("/") else { return nil }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        return VaultPathBoundary.relativePath(of: url, in: root) != nil ? url : nil
    }
}

/// Obsidian's Daily Notes settings (.obsidian/daily-notes.json): folder and date format.
public struct DailyNoteConfig: Equatable, Sendable {
    public var folder: String
    public var format: String

    public init(folder: String = "", format: String = "YYYY-MM-DD") {
        self.folder = folder
        self.format = format.isEmpty ? "YYYY-MM-DD" : format
    }

    public static func read(vault: URL) -> DailyNoteConfig {
        let file = vault.appendingPathComponent(".obsidian/daily-notes.json")
        guard VaultPathBoundary.relativePath(of: file, in: vault) != nil,
              let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return DailyNoteConfig() }
        return DailyNoteConfig(folder: json["folder"] as? String ?? "", format: json["format"] as? String ?? "")
    }

    /// Supports the common Moment tokens: YYYY, YY, MM, M, DD, D, and [literal] text.
    public func relativePath(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let (year, month, day) = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var out = ""
        var rest = Substring(format)
        while !rest.isEmpty {
            if rest.hasPrefix("[") , let close = rest.firstIndex(of: "]") {
                out += rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
            } else if rest.hasPrefix("YYYY") { out += String(format: "%04d", year); rest = rest.dropFirst(4) }
            else if rest.hasPrefix("YY") { out += String(format: "%02d", year % 100); rest = rest.dropFirst(2) }
            else if rest.hasPrefix("MM") { out += String(format: "%02d", month); rest = rest.dropFirst(2) }
            else if rest.hasPrefix("M") { out += "\(month)"; rest = rest.dropFirst() }
            else if rest.hasPrefix("DD") { out += String(format: "%02d", day); rest = rest.dropFirst(2) }
            else if rest.hasPrefix("D") { out += "\(day)"; rest = rest.dropFirst() }
            else { out.append(rest.removeFirst()) }
        }
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (folder.isEmpty ? "" : folder + "/") + out + ".md"
    }
}

/// Finds second brains on this Mac without reading note contents: Obsidian's own vault list,
/// folders with `.obsidian` or `logseq/`, Notion exports, plain Markdown folders, Bear and Apple Notes.
public enum BrainDetector {
    public static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              extraRoots: [URL] = [], maxDepth: Int = 3) -> [BrainSource] {
        var found: [BrainSource] = []
        var seen = Set<String>()
        func add(_ source: BrainSource) {
            let key = URL(fileURLWithPath: source.path).resolvingSymlinksInPath().path
            if seen.insert(key).inserted { found.append(source) }
        }

        let support = home.appendingPathComponent("Library/Application Support")
        for path in obsidianVaults(config: support.appendingPathComponent("obsidian/obsidian.json"))
        where FileManager.default.fileExists(atPath: path) {
            add(BrainSource(kind: .obsidian, name: URL(fileURLWithPath: path).lastPathComponent, path: path))
        }

        let roots = [
            "Documents", "Desktop", "Notes", "Obsidian", "Dropbox",
            "Library/Mobile Documents/iCloud~md~obsidian/Documents",
            "Library/Mobile Documents/iCloud~com~logseq~logseq/Documents",
            "Library/Mobile Documents/com~apple~CloudDocs",
        ].map { home.appendingPathComponent($0) } + extraRoots
        var budget = 3000
        for root in roots { scan(root, depth: 0, maxDepth: maxDepth, budget: &budget, add: add) }

        let groups = home.appendingPathComponent("Library/Group Containers")
        let bear = groups.appendingPathComponent("9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite")
        if FileManager.default.fileExists(atPath: bear.path) {
            add(BrainSource(kind: .bear, name: "Bear", path: bear.deletingLastPathComponent().path))
        }
        let notes = groups.appendingPathComponent("group.com.apple.notes")
        if FileManager.default.fileExists(atPath: notes.appendingPathComponent("NoteStore.sqlite").path) {
            add(BrainSource(kind: .appleNotes, name: "Apple Notes", path: notes.path))
        }
        return found
    }

    /// Vault paths from Obsidian's own list.
    public static func obsidianVaults(config: URL) -> [String] {
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: Any] else { return [] }
        return vaults.values.compactMap { ($0 as? [String: Any])?["path"] as? String }.sorted()
    }

    /// What kind of second brain a folder is, judged from its top level only.
    public static func classify(_ folder: URL) -> BrainSource.Kind? {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path) else { return nil }
        if names.contains(".obsidian") { return .obsidian }
        if names.contains("logseq"), files.fileExists(atPath: folder.appendingPathComponent("logseq/config.edn").path) { return .logseq }
        if names.contains(".git") { return nil }  // a code repo's docs, not a notes folder
        let markdown = names.filter { $0.lowercased().hasSuffix(".md") }
        if markdown.filter(isNotionName).count >= 3 { return .notion }
        if markdown.count >= 5 { return .markdown }
        return nil
    }

    /// Notion exports name files "Title 0123456789abcdef0123456789abcdef.md".
    static func isNotionName(_ name: String) -> Bool {
        let stem = name.dropLast(3)
        guard let space = stem.lastIndex(of: " ") else { return false }
        let tail = stem[stem.index(after: space)...]
        return tail.count == 32 && tail.allSatisfy(\.isHexDigit)
    }

    private static let skip: Set<String> = ["Library", "node_modules", "build", "dist", "DerivedData", "Applications", "Pictures", "Movies", "Music"]

    private static func scan(_ folder: URL, depth: Int, maxDepth: Int, budget: inout Int, add: (BrainSource) -> Void) {
        guard budget > 0 else { return }
        budget -= 1
        if let kind = classify(folder) {
            add(BrainSource(kind: kind, name: folder.lastPathComponent, path: folder.path))
            return  // don't look for vaults inside a vault
        }
        guard depth < maxDepth,
              let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values?.isDirectory == true, values?.isPackage != true, !skip.contains(child.lastPathComponent) else { continue }
            scan(child, depth: depth + 1, maxDepth: maxDepth, budget: &budget, add: add)
        }
    }
}

/// A note that matched a search, with a short snippet to quote.
public struct NoteHit: Equatable, Sendable {
    public var title: String
    public var path: String
    public var snippet: String
    public var score: Int

    public init(title: String, path: String, snippet: String, score: Int) {
        self.title = title
        self.path = path
        self.snippet = snippet
        self.score = score
    }
}

/// Plain scoring for note search: title hits count three times; the snippet is the line with most hits.
public enum NoteRanker {
    static let stop: Set<String> = ["the", "and", "for", "what", "that", "with", "about", "from", "this", "have", "your", "you",
                                    "are", "was", "how", "can", "does", "did", "my", "me", "is", "it", "of", "to", "in", "on", "a", "an",
                                    "zeus", "please", "tell", "show", "find", "notes", "note", "brain"]

    public static func terms(_ query: String) -> [String] {
        query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    public static func rank(title: String, path: String, text: String, terms: [String]) -> NoteHit? {
        guard !terms.isEmpty else { return nil }
        let lowerTitle = title.lowercased()
        var score = 0
        var best = (count: 0, line: "")
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(4000) {
            let lower = line.lowercased()
            let count = terms.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
            score += count
            // Prefer body lines over headings for the quote.
            let weight = count * 2 + (count > 0 && !lower.hasPrefix("#") ? 1 : 0)
            if weight > best.count { best = (weight, String(line)) }
        }
        score += terms.reduce(0) { $0 + (lowerTitle.contains($1) ? 3 : 0) }
        guard score > 0 else { return nil }
        let snippet = best.line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "#-*>")))
        return NoteHit(title: title, path: path, snippet: String(snippet.prefix(240)), score: score)
    }
}
