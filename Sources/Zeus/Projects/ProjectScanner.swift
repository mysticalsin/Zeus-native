import AppKit
import ZeusCore

/// Tony's code projects (git repos up to three folders deep under ~/dev, ~/Developer, ~/Documents,
/// ~/Projects and ~/Desktop), found in the background and cached on disk so a lookup right after
/// launch already works. A lookup is an in-memory fuzzy match; the scan never runs on the hot path.
/// Extra names live in UserDefaults `projects.aliases` ({alias: path}).
final class ProjectScanner: @unchecked Sendable {
    static let shared = ProjectScanner()

    private struct Cache: Codable {
        var scannedAt: Date
        var entries: [ProjectEntry]
    }

    private let lock = NSLock()
    private var index: ProjectIndex
    private var scannedAt = Date.distantPast
    private var refreshing = false
    private var lastMissRefresh = Date.distantPast
    private var timer: Timer?
    private let cacheURL: URL
    private let roots: [URL]
    private let defaults: UserDefaults

    /// Tests pass fake roots and a temp cache; the app uses the real ones.
    init(roots: [URL]? = nil, cacheURL: URL? = nil, defaults: UserDefaults = .standard) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = roots ?? ProjectIndex.defaultRoots.map { home.appendingPathComponent($0, isDirectory: true) }
        self.cacheURL = cacheURL ?? ZeusPaths.supportDirectory.appendingPathComponent("projects.json")
        self.defaults = defaults
        index = ProjectIndex([])
        if let data = try? Data(contentsOf: self.cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            index = ProjectIndex(cache.entries, userAliases: userAliases())
            scannedAt = cache.scannedAt
        }
    }

    var count: Int { lock.withLock { index.count } }
    var entries: [ProjectEntry] { lock.withLock { index.entries } }

    @MainActor
    func start() {
        refreshInBackground(force: false)
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refreshInBackground(force: true) }
    }

    func userAliases() -> [String: String] {
        defaults.dictionary(forKey: "projects.aliases") as? [String: String] ?? [:]
    }

    /// Rescans off the main thread. A fresh cache (under 10 minutes old) is left alone unless forced.
    func refreshInBackground(force: Bool) {
        guard lock.withLock({ () -> Bool in
            if refreshing || (!force && Date().timeIntervalSince(scannedAt) < 600 && !index.isEmpty) { return false }
            refreshing = true
            return true
        }) else { return }
        let roots = roots
        let cacheURL = cacheURL
        Task.detached(priority: .utility) { [weak self] in
            let started = Date()
            let found = ProjectIndex.scan(roots: roots)
            guard let self else { return }
            let next = ProjectIndex(found, userAliases: self.userAliases())
            self.lock.withLock {
                self.index = next
                self.scannedAt = Date()
                self.refreshing = false
            }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(Cache(scannedAt: Date(), entries: found)) { try? data.write(to: cacheURL, options: .atomic) }
            NSLog("[ZEUS] projects: %d repos in %.0fms", found.count, Date().timeIntervalSince(started) * 1000)
        }
    }

    /// The project `name` most likely means. A miss triggers one rescan (at most once a minute) for next time.
    func lookup(_ name: String) -> ProjectIndex.Lookup {
        let index = lock.withLock { self.index }
        let result = index.lookup(name)
        if case .none = result {
            let due = lock.withLock { () -> Bool in
                if Date().timeIntervalSince(lastMissRefresh) < 60 { return false }
                lastMissRefresh = Date()
                return true
            }
            if due { refreshInBackground(force: true) }
        }
        return result
    }

    /// A path Tony said or typed ("~/dev/zeus"), if it is a folder that exists.
    static func existingFolder(_ text: String) -> URL? {
        guard let path = CodeCommand.expandPath(text) else { return nil }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? URL(fileURLWithPath: path, isDirectory: true) : nil
    }
}
