import Foundation

/// The result of writing a prompt to a process. A thrown write is a failure, not silence.
public enum StdinWrite {
    /// Red: a thrown write is discarded and looks like success.
    public static func attempt(_ write: () throws -> Void) -> String? {
        do { try write() } catch { return nil }
        return nil
    }
}
