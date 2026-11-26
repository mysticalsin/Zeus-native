import Foundation

/// Where a finished dictation goes.
///
/// A writable focused field receives the words. The clipboard is the fallback when that
/// field cannot take them, or when the turn is no longer current. A clipboard result is
/// not an insertion: `dictate-file` reports `ERROR nothing inserted`.
public enum FocusedFieldWrite {
    public enum Choice: Equatable, Sendable {
        case writeField
        case clipboard
    }

    public static func choose(turnCurrent: Bool, fieldWritable: Bool) -> Choice {
        guard turnCurrent, fieldWritable else { return .clipboard }
        return .writeField
    }

    /// History marks `inserted` only when the focused-field write landed.
    public static func inserted(choice: Choice, fieldWriteLanded: Bool) -> Bool {
        choice == .writeField && fieldWriteLanded
    }
}
