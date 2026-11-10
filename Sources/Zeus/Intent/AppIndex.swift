import AppKit
import ZeusCore

/// The apps on this Mac, by name and alias, for the fast path ("open VS Code"). Built off the main
/// thread at launch and every 15 minutes (and once more after a miss), never on the hot path:
/// a lookup is an in-memory fuzzy match under a lock, well under a millisecond.
final class AppIndex: @unchecked Sendable {
    static let shared = AppIndex()

    enum Lookup: Equatable {
        case app(AppEntry)
        /// Two different apps are about as likely: ask instead of guessing.
        case ambiguous(AppEntry, AppEntry)
        case none
    }

    private let lock = NSLock()
    private var matcher: AppMatcher
    private var entries: [AppEntry]
    private var refreshing = false
    private var lastMissRefresh = Date.distantPast
    private var timer: Timer?

    /// Tests pass a fake list; the app starts empty and fills in the background.
    init(entries: [AppEntry] = []) {
        self.entries = entries
        matcher = AppMatcher(entries)
    }

    var count: Int { lock.withLock { matcher.count } }

    @MainActor
    func start() {
        refreshInBackground()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.refreshInBackground() }
    }

    func refreshInBackground() {
        guard lock.withLock({ () -> Bool in
            if refreshing { return false }
            refreshing = true
            return true
        }) else { return }
        Task.detached(priority: .utility) { [weak self] in
            let started = Date()
            let found = AppIndex.scan()
            guard let self else { return }
            let matcher = AppMatcher(found)
            self.lock.withLock {
                self.entries = found
                self.matcher = matcher
                self.refreshing = false
            }
            NSLog("[ZEUS] fast: app index %d apps in %.0fms", matcher.count, Date().timeIntervalSince(started) * 1000)
        }
    }

    /// The installed app `name` most likely means.
    func lookup(_ name: String) -> Lookup {
        let matcher = lock.withLock { self.matcher }
        let ranked = matcher.ranked(name)
        guard let top = ranked.first else { missed(); return .none }
        if AppMatcher.isAmbiguous(ranked) {
            // Two clear candidates: ask instead of guessing. Two weak ones: hand it on.
            if ranked[1].score >= AppMatcher.threshold { return .ambiguous(top.entry, ranked[1].entry) }
            missed()
            return .none
        }
        if top.score >= AppMatcher.threshold { return .app(top.entry) }
        missed()
        return .none
    }

    /// A running app (regular, with a Dock icon) matching `name`, for quit and hide.
    @MainActor
    static func running(_ name: String) -> NSRunningApplication? {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
        let entries = apps.map { AppEntry(name: $0.localizedName ?? "", bundleID: $0.bundleIdentifier ?? "pid\($0.processIdentifier)") }
        guard let match = AppMatcher(entries).confident(name) else { return nil }
        return apps.first { ($0.bundleIdentifier ?? "pid\($0.processIdentifier)") == match.entry.bundleID }
    }

    private func missed() {
        // A new app may have arrived since the last scan; look again, at most once a minute.
        let due = lock.withLock { () -> Bool in
            guard Date().timeIntervalSince(lastMissRefresh) > 60 else { return false }
            lastMissRefresh = Date()
            return true
        }
        if due { refreshInBackground() }
    }

    // MARK: Scan

    static var searchFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                home.appendingPathComponent("Applications").path, "/System/Library/CoreServices/Applications"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Every .app in the usual folders (and one folder deep, for "Adobe Photoshop 2025/…"), plus Finder.
    static func scan(folders: [URL] = searchFolders) -> [AppEntry] {
        let files = FileManager.default
        var found: [AppEntry] = []
        func add(_ url: URL) {
            let plist = url.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
                  let bundleID = info["CFBundleIdentifier"] as? String else { return }
            let display = files.displayName(atPath: url.path)
            let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
            var aliases: [String] = []
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let other = info[key] as? String, !other.isEmpty, other != name { aliases.append(other) }
            }
            found.append(AppEntry(name: name, bundleID: bundleID, path: url.path, aliases: aliases))
        }
        for folder in folders {
            guard let items = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "app" { add(item); continue }
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      let inner = try? files.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for app in inner where app.pathExtension == "app" { add(app) }
            }
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        // /Applications first, so its copy wins over a duplicate elsewhere.
        return found
    }
}

