import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Where `zeus debug screenshot` may write. A request may name any path, so the path is judged here
/// before anything is created: absolute, no traversal, and (after resolving every symlink that
/// exists) strictly inside the app's own caches folder or a folder the owner chose at launch.
public enum DebugOutputPath {
    public enum Rejection: Error, Equatable, Sendable {
        case empty
        case notAbsolute
        case traversal
        case outsideAllowedFolders
    }

    /// The environment variable that names one more allowed folder. A program cannot change another
    /// process's environment, so only whoever launched Zeus can set it.
    public static let ownerFolderVariable = "ZEUS_DEBUG_SCREENSHOT_DIR"

    /// Caches folder of the app plus, when the owner chose one at launch, that folder.
    /// A chosen folder must be absolute, free of `..` and not the filesystem root.
    public static func allowedFolders(cachesDirectory: String, environment: [String: String]) -> [String] {
        var folders = [appCachesFolder(cachesDirectory: cachesDirectory)]
        if let chosen = environment[ownerFolderVariable], let parts = PathContainment.components(chosen), !parts.isEmpty {
            folders.append("/" + parts.joined(separator: "/"))
        }
        return folders
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
    public static func validate(_ requested: String, allowedFolders: [String],
                                resolve: (String) -> String? = realPath) -> Result<String, Rejection> {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.contains("\u{0}") || expanded.split(separator: "/").contains("..") { return .failure(.traversal) }
        guard let parts = PathContainment.components(expanded) else { return .failure(.notAbsolute) }
        let target = resolved("/" + parts.joined(separator: "/"), resolve: resolve)
        for folder in allowedFolders {
            guard let folderParts = PathContainment.components(folder), !folderParts.isEmpty else { continue }
            let root = resolved("/" + folderParts.joined(separator: "/"), resolve: resolve)
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
