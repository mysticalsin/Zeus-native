import Foundation

/// Spoken to-do commands, handled on the Mac before any model: "add these to-dos: call Ana
/// tomorrow, send the invoice Friday and book the dentist". English, French and Portuguese.
/// Each answer is read from `TodoVoiceBox`.
public enum TodoVoice {
    public enum Command: Equatable, Sendable {
        case add([String])
        case today
        case brief
        case complete(String)
    }

    public static func parse(_ utterance: String) -> Command? {
        TodoVoiceBox.parse(utterance)
    }

    /// One phrase, many to-dos: commas, semicolons, new lines, "and", "then", "et", "e".
    public static func split(_ text: String) -> [String] {
        TodoVoiceBox.split(text)
    }

    /// "to call Anna" from a bare "call Anna" lead should not keep the filler "to".
    public static func stripLeadingTo(_ text: String) -> String {
        TodoVoiceBox.stripLeadingTo(text)
    }
}
