import Foundation

/// How a later dictate-file writes a field that already holds the first insert.
///
/// The first ok sets the whole value. A warm run that sets the whole value again
/// comes back as a failed focused-field write, then clipboard-only, then
/// `ERROR nothing inserted`. A field that already has text is written at the caret.
public enum WarmFieldInsert {
    public enum Step: Equatable, Sendable {
        case setValue(String)
        case setSelectedText(String)
    }

    /// Ordered attempts. Empty when the words must not be written.
    public static func steps(text: String, current: String, valueSettable: Bool,
                             selectedTextSettable: Bool, secure: Bool) -> [Step] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !secure else { return [] }
        if current.isEmpty {
            var ordered: [Step] = []
            if valueSettable { ordered.append(.setValue(trimmed)) }
            if selectedTextSettable { ordered.append(.setSelectedText(trimmed)) }
            return ordered
        }
        var ordered: [Step] = []
        if selectedTextSettable { ordered.append(.setSelectedText(trimmed)) }
        if valueSettable { ordered.append(.setValue(current + trimmed)) }
        return ordered
    }

    /// The write landed only when the field actually holds the words.
    public static func landed(fieldValue: String?, selectedText: String?, expected: String) -> Bool {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let fieldValue, fieldValue.contains(trimmed) { return true }
        if let selectedText, selectedText.contains(trimmed) { return true }
        return false
    }
}
