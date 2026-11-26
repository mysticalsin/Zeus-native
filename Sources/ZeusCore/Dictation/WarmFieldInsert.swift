import Foundation

/// How a later dictate-file writes a field that already holds the first insert.
///
/// The first ok sets the whole value. A warm run that sets the whole value again
/// comes back as a failed focused-field write, then clipboard-only, then
/// `ERROR nothing inserted`. A field that already has text is written at the caret.
/// The steps and the landed check are read from `WarmFieldInsertBox`.
public enum WarmFieldInsert {
    public enum Step: Equatable, Sendable {
        case setValue(String)
        case setSelectedText(String)
    }

    /// Ordered attempts. Empty when the words must not be written.
    public static func steps(text: String, current: String, valueSettable: Bool,
                             selectedTextSettable: Bool, secure: Bool) -> [Step] {
        WarmFieldInsertBox.steps(text: text, current: current, valueSettable: valueSettable,
                                 selectedTextSettable: selectedTextSettable, secure: secure)
    }

    /// The write landed only when the field actually holds the words.
    public static func landed(fieldValue: String?, selectedText: String?, expected: String) -> Bool {
        WarmFieldInsertBox.landed(fieldValue: fieldValue, selectedText: selectedText, expected: expected)
    }
}
