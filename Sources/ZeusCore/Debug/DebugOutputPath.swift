import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Where `zeus debug screenshot` may write. A request may name any path, so the path is judged here
/// before anything is created: absolute, no traversal, and (after resolving every symlink that
/// exists) strictly inside the app's own caches folder or a folder the owner chose at launch.
/// A chosen folder may not be the home folder, `~/Library`, the login item folder (`~/Library/LaunchAgents`)
/// or any folder above them, nor anything inside the login item folder, nor a hidden folder under home,
/// because a PNG written to the right name there would replace a shell startup file, a login item or a
/// key. Other folders inside home and `~/Library` (Documents, Library/Caches) are allowed.
public enum DebugOutputPath {
    public enum Rejection: Error, Equatable, Sendable {
        case empty
        case notAbsolute
        case traversal
        case outsideAllowedFolders
    }

    /// The environment variable that names one more allowed folder. Debug and test builds read it
    /// when Zeus starts. Release builds ignore it. It is set by whoever launched Zeus, or by the login
    /// session's environment, which any program of this user can change for the next start, so the
    /// folder is also checked against the broad folders above and a request still has to name a file
    /// strictly inside it.
    public static let ownerFolderVariable = "ZEUS_DEBUG_SCREENSHOT_DIR"

    /// Caches folder of the app plus, when the owner chose one at launch, that folder.
    /// A chosen folder must be absolute, free of `..`, not the filesystem root and not a broad folder
    /// (see `isBroad`); symlinks are resolved before that check.
    public static func allowedFolders(cachesDirectory: String, environment: [String: String],
                                      homeDirectory: String = NSHomeDirectory(),
                                      resolve: (String) -> String? = realPath) -> [String] {
        var folders = [appCachesFolder(cachesDirectory: cachesDirectory)]
        if let chosen = SupportOverride.resolved(ownerFolderVariable, environment: SupportOverrideMap(environment)),
           let parts = PathContainment.components(chosen), !parts.isEmpty {
            // The resolved path is both checked and kept, so the check judges the folder that is later used.
            let path = resolved("/" + parts.joined(separator: "/"), resolve: resolve)
            if !isBroad(path, home: resolved(homeDirectory, resolve: resolve)) { folders.append(path) }
        }
        return folders
    }

    /// True for the home folder, `~/Library`, `~/Library/LaunchAgents`, every folder above them, anything
    /// inside the login item folder and any hidden folder directly under home (`.ssh`, `.config`).
    /// Both paths are absolute and symlink-resolved.
    static func isBroad(_ folder: String, home: String) -> Bool {
        guard let parts = PathContainment.components(folder), let homeParts = PathContainment.components(home) else { return true }
        let agents = homeParts + ["Library", "LaunchAgents"]
        if parts.count <= agents.count, Array(agents.prefix(parts.count)) == parts { return true }
        if parts.count >= agents.count, Array(parts.prefix(agents.count)) == agents { return true }
        if parts.count > homeParts.count, Array(parts.prefix(homeParts.count)) == homeParts,
           parts[homeParts.count].hasPrefix(".") { return true }
        return false
    }

    public static func appCachesFolder(cachesDirectory: String) -> String {
        let base = cachesDirectory.hasSuffix("/") ? String(cachesDirectory.dropLast()) : cachesDirectory
        return base + "/" + ZeusPaths.bundleIdentifier
    }

    /// The base used when the request names no path.
    public static func defaultBase(cachesDirectory: String, token: String) -> String {
        appCachesFolder(cachesDirectory: cachesDirectory) + "/DebugScreenshots/zeus-screenshot-\(token)"
    }

    /// Accepts `requested` only when it ends up strictly inside one of `allowedFolders`. Returns the
    /// symlink-resolved path, which is what should be written, so a link swapped in later cannot move it.
    /// Each allowed folder is resolved again here and must still not be a broad folder (see `isBroad`), because
    /// a folder that was fine when the list was made can be replaced by a link before the request arrives.
    public static func validate(_ requested: String, allowedFolders: [String], homeDirectory: String = NSHomeDirectory(),
                                resolve: (String) -> String? = realPath) -> Result<String, Rejection> {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.contains("\u{0}") || expanded.split(separator: "/").contains("..") { return .failure(.traversal) }
        guard let parts = PathContainment.components(expanded) else { return .failure(.notAbsolute) }
        let target = resolved("/" + parts.joined(separator: "/"), resolve: resolve)
        let home = resolved(homeDirectory, resolve: resolve)
        for folder in allowedFolders {
            guard let folderParts = PathContainment.components(folder), !folderParts.isEmpty else { continue }
            let root = resolved("/" + folderParts.joined(separator: "/"), resolve: resolve)
            if isBroad(root, home: home) { continue }
            if PathContainment.isInside(target, root: root) { return .success(target) }
        }
        return .failure(.outsideAllowedFolders)
    }

    /// The real path of the deepest part that exists (every link followed), with the rest appended.
    /// The final name is followed too when it already exists, so a link there cannot lead outside.
    static func resolved(_ path: String, resolve: (String) -> String?) -> String {
        var rest: [String] = []
        var current = path
        while true {
            if let real = resolve(current) {
                return rest.reversed().reduce(real) { $0 == "/" ? "/" + $1 : $0 + "/" + $1 }
            }
            guard current != "/" else { return path }
            rest.append((current as NSString).lastPathComponent)
            current = (current as NSString).deletingLastPathComponent
            if current.isEmpty { current = "/" }
        }
    }

    /// `realpath(3)`: nil when the path does not exist.
    public static func realPath(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
