import Foundation

/// Paths beneath a vault selected by the person. The selected root may itself be a
/// symlink, but links below it must not redirect reads or writes to another note or folder.
enum VaultPathBoundary {
    static func relativePath(of url: URL, in root: URL) -> String? {
        guard url.isFileURL, root.isFileURL else { return nil }
        // Do not normalize away a symlink/.. pair and then let the caller use the original
        // spelling for I/O: the filesystem would traverse the link before interpreting .. .
        guard !url.pathComponents.contains(".."), !root.pathComponents.contains("..") else { return nil }
        let base = root.standardizedFileURL
        let target = url.standardizedFileURL
        let rootParts = base.pathComponents
        let parts = target.pathComponents
        guard parts.count > rootParts.count, parts.starts(with: rootParts) else { return nil }
        let relative = parts.dropFirst(rootParts.count)
        var componentURL = base
        for component in relative {
            componentURL.appendPathComponent(component)
            // Also rejects dangling links, which fileExists(atPath:) does not detect.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                return nil
            }
        }
        return relative.joined(separator: "/")
    }
}
