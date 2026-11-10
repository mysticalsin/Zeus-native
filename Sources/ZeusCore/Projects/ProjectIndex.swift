import Foundation

/// A code project (a git repo) on this Mac, as the voice commands know it.
public struct ProjectEntry: Codable, Equatable, Sendable {
    public var name: String
    public var path: String
    /// Extra names it answers to ("polyglot" for ~/Documents/Polyglot is the folder name itself;
    /// these are for the ones Tony adds).
    public var aliases: [String]

    public init(name: String, path: String, aliases: [String] = []) {
        self.name = name; self.path = path; self.aliases = aliases
    }
}

/// Fuzzy project-name matching with a confidence score, on the same scoring as `AppMatcher`
/// (exact names 1, spacing differences 0.97, word prefixes, initials, small mishearings).
/// "zeus" finds ~/dev/zeus; "zeus mac" finds a repo called zeus-mac. A repo name also answers to
/// its first word ("zeus" for zeus-mac) when that is unambiguous, via the shorter-name tie-break.
public struct ProjectIndex: Sendable {
    public enum Lookup: Equatable, Sendable {
        case project(ProjectEntry)
        case ambiguous(ProjectEntry, ProjectEntry)
        case none
    }

    public struct Match: Equatable, Sendable {
        public let entry: ProjectEntry
        public let score: Double
    }

    /// Below this a project name is not trusted: the request goes on to the LLM.
    public static let threshold = AppMatcher.threshold

    public let entries: [ProjectEntry]
    private let matcher: AppMatcher
    private let byPath: [String: ProjectEntry]

    public init(_ entries: [ProjectEntry], userAliases: [String: String] = [:]) {
        var merged = entries
        // Alias → path: add the alias to the entry at that path, if it is known.
        for (alias, path) in userAliases {
            if let index = merged.firstIndex(where: { $0.path == path }), !merged[index].aliases.contains(alias) {
                merged[index].aliases.append(alias)
            }
        }
        self.entries = merged
        var byPath: [String: ProjectEntry] = [:]
        for entry in merged { byPath[entry.path] = entry }
        self.byPath = byPath
        // AppMatcher keys entries by bundle ID; the path plays that part here.
        matcher = AppMatcher(merged.map {
            AppEntry(name: $0.name, bundleID: $0.path, path: $0.path, aliases: $0.aliases + Self.derivedAliases($0.name))
        })
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// "zeus-mac" → "zeus mac", "zeus"; "PolyglotApp" → "polyglot app", "polyglot".
    static func derivedAliases(_ name: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in name {
            if let previous, character.isUppercase, previous.isLowercase { spaced.append(" ") }
            spaced.append(character)
            previous = character
        }
        let tokens = AppMatcher.normalize(spaced).split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return [] }
        var out = [tokens.joined(separator: " ")]
        if let first = tokens.first, first.count >= 3 { out.append(first) }
        return out
    }

    public func ranked(_ query: String, limit: Int = 3) -> [Match] {
        matcher.ranked(query, limit: limit).compactMap { match in
            byPath[match.entry.path].map { Match(entry: $0, score: match.score) }
        }
    }

    /// The best project for `query` and its confidence, ambiguity already applied.
    public func best(_ query: String) -> Match? {
        guard let match = matcher.best(query), let entry = byPath[match.entry.path] else { return nil }
        return Match(entry: entry, score: match.score)
    }

    public func confident(_ query: String, threshold: Double = ProjectIndex.threshold) -> Match? {
        guard let match = best(query), match.score >= threshold else { return nil }
        return match
    }

    /// A confident project, an ambiguous pair, or nothing.
    public func lookup(_ query: String) -> Lookup {
        let list = ranked(query)
        guard let top = list.first else { return .none }
        if AppMatcher.isAmbiguous(matcher.ranked(query)), list.count > 1, top.score >= Self.threshold {
            return .ambiguous(top.entry, list[1].entry)
        }
        guard top.score >= Self.threshold else { return .none }
        return .project(top.entry)
    }

    // MARK: Finding projects on disk

    public static let defaultRoots = ["dev", "Developer", "Documents", "Projects", "Desktop"]
    public static let skippedFolders: Set<String> = [
        "node_modules", ".build", "Library", "Pods", "DerivedData", ".venv", "venv", "__pycache__",
        ".Trash", "Applications", "Pictures", "Music", "Movies", "target", "dist", "build", ".git",
    ]

    /// Git repos up to `maxDepth` levels under each root (a root's children are depth 1). A repo's
    /// insides are not searched. Hidden folders and `skippedFolders` are never entered. Stable order.
    public static func scan(roots: [URL], maxDepth: Int = 3, fileManager: FileManager = .default) -> [ProjectEntry] {
        var found: [ProjectEntry] = []
        var seen = Set<String>()
        func isRepo(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.appendingPathComponent(".git").path)
        }
        func visit(_ url: URL, depth: Int) {
            guard let children = try? fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = child.lastPathComponent
                guard !skippedFolders.contains(name),
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let real = child.resolvingSymlinksInPath().path
                if isRepo(child) {
                    if seen.insert(real).inserted { found.append(ProjectEntry(name: name, path: child.standardizedFileURL.path)) }
                } else if depth < maxDepth {
                    visit(child, depth: depth + 1)
                }
            }
        }
        for root in roots {
            if isRepo(root) {
                if seen.insert(root.resolvingSymlinksInPath().path).inserted {
                    found.append(ProjectEntry(name: root.lastPathComponent, path: root.standardizedFileURL.path))
                }
                continue
            }
            visit(root, depth: 1)
        }
        return found
    }

    /// "~/dev/zeus", for speech and cards.
    public static func tilde(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
