import Foundation

/// Quoting for text that ends up inside a generated shell script or an AppleScript string.
/// Everything a person or a model said (a task, a path, a command) goes through here, never
/// into a script as is, so a quote or `$(...)` in a task stays text.
public enum ShellQuote {
    /// POSIX single quotes: nothing is special inside them, and a `'` becomes `'\''`.
    public static func single(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The inside of an AppleScript string literal (backslash and double quote escaped).
    public static func appleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The inside of a double-quoted YAML scalar.
    public static func yaml(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
