import Foundation

/// Home directory for the owner's local build tree. `$HOME` when it is set, otherwise
/// `NSHomeDirectory()`. On the owner's Mac those are the same directory, so a path built from
/// this plus a historical relative suffix stays the path the app already used.
enum LocalHome {
    static func path() -> String {
        if let raw = getenv("HOME") {
            let home = String(cString: raw)
            if !home.isEmpty { return home }
        }
        return NSHomeDirectory()
    }

    static func appending(_ relative: String, isDirectory: Bool = false) -> URL {
        URL(fileURLWithPath: path(), isDirectory: true)
            .appendingPathComponent(relative, isDirectory: isDirectory)
    }
}
