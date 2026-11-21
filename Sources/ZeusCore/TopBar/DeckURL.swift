import Foundation

/// The deck address the reader may open. Parsed as URL components, then checked.
public enum DeckURL {
    public static func isPresentation(_ url: String) -> Bool {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              host == "docs.google.com" else { return false }
        return standardized(components.path).hasPrefix("/presentation/")
    }

    /// Drops `.` and `..` so a path cannot climb out and still match the prefix.
    static func standardized(_ path: String) -> String {
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(String(part))
        }
        return "/" + parts.joined(separator: "/")
    }
}
