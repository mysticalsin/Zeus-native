import Foundation

/// Hard length limits from the Ultron persona spec (PERSONA-ULTRON.md section 5). The model is
/// instructed in `ZeusPersona`, but fallback brains ignore it; this is the floor on what is spoken
/// and logged (QA7 round 12: thanks/reminders/jokes over the sentence budget).
public enum PersonaReplyClamp: Sendable {
    public enum Kind: Sendable {
        case action
        case gratitude
        case chat
    }

    public static func kind(for transcript: String) -> Kind {
        let text = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("thank") || text == "thanks" || text.contains("thank you") { return .gratitude }
        if text.contains("remind me") || text.contains("set a timer") || text.contains("set timer")
            || text.contains("timer for") {
            return .action
        }
        return .chat
    }

    /// A spoken reply is one to three sentences, even when the owner asks for detail.
    public static let voiceMaxSentences = 3

    public static func maxSentences(transcript: String, personality: ZeusPersonality) -> Int {
        guard personality == .ultron else {
            return kind(for: transcript) == .chat ? 4 : 1
        }
        switch kind(for: transcript) {
        case .action, .gratitude: return 1
        case .chat: return wantsDetail(transcript) ? voiceMaxSentences : 2
        }
    }

    /// "Explain...", "in detail", "walk me through": the one case a chat answer may run past two sentences.
    static func wantsDetail(_ transcript: String) -> Bool {
        let text = transcript.lowercased()
        return ["explain", "in detail", "in depth", "tell me more", "walk me through", "step by step", "elaborate"]
            .contains { text.contains($0) }
    }

    /// Keeps at most `maxSentences` complete sentences; drops trailing partial clauses.
    public static func clamp(_ text: String, maxSentences: Int) -> String {
        guard maxSentences > 0 else { return "" }
        let trimmed = PersonaCompliance.stripOminousHedges(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "–", with: ", ")
        guard !trimmed.isEmpty else { return trimmed }
        var sentences: [String] = []
        var current = ""
        for character in trimmed {
            current.append(character)
            if ".!?".contains(character) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { sentences.append(piece) }
                current = ""
                if sentences.count >= maxSentences { break }
            }
        }
        if sentences.count < maxSentences, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return sentences.prefix(maxSentences).joined(separator: " ")
    }

    public static func clamp(_ text: String, transcript: String, personality: ZeusPersonality) -> String {
        clamp(text, maxSentences: maxSentences(transcript: transcript, personality: personality))
    }
}
