import Foundation

/// The result of writing a prompt to a process. A thrown write is a failure, not silence.
public enum StdinWrite {
    public static func attempt(_ write: () throws -> Void) -> String? {
        do {
            try write()
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
