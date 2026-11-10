import Foundation

/// Local Whisper prompt-echo recovery adapted from OpenWhispr's MIT-licensed
/// dictionaryEchoFilter.js and audioManager.js at e2f96ef01579f88a187a4179b357119208b50ab7.
/// See NOTICES.md. A retry decodes the same audio without vocabulary bias; it never
/// removes words merely because they appear in a dictionary and never calls a cloud engine.
public enum WhisperPromptRecovery {
    public struct Attempt: Equatable, Sendable {
        public let prompt: String
        public let skipVoiceActivityDetection: Bool
    }

    /// A whole hint-list recital or a looped hint word is suspicious. One or two ordinary
    /// dictionary terms are valid short dictation, so they do not trigger a retry.
    public static func shouldRetry(_ text: String, sentPrompt: String) -> Bool {
        let prompt = withoutNamesPrefix(sentPrompt)
        let words = normalized(withoutNamesPrefix(text)).split(separator: " ").map(String.init)
        let promptWords = Set(normalized(prompt).split(separator: " ").map(String.init))
        guard words.count >= 3, !promptWords.isEmpty else { return false }
        let unique = Set(words)
        let shared = unique.intersection(promptWords).count
        guard Double(shared) / Double(unique.count) >= 0.9 else { return false }
        let terms = prompt.components(separatedBy: CharacterSet(charactersIn: ",、，"))
            .map(normalized).filter { !$0.isEmpty }
        let wholeList = terms.count >= 3 && Double(shared) / Double(promptWords.count) >= 0.7
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        return wholeList || counts.values.contains { $0 >= 3 }
    }

    /// At most two local decodes. A prompt-free answer is kept even when it confirms the
    /// same dictionary words: those can be what the person actually said. Errors propagate
    /// through the engine's existing error path; no suspect text is silently substituted.
    public static func transcribe(sentPrompt: String, decode: (Attempt) async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let initial = try await decode(Attempt(prompt: sentPrompt, skipVoiceActivityDetection: false))
        try Task.checkCancellation()
        guard shouldRetry(initial, sentPrompt: sentPrompt) else { return initial }
        let recovered = try await decode(Attempt(prompt: "", skipVoiceActivityDetection: true))
        try Task.checkCancellation()
        return recovered
    }

    private static func withoutNamesPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("names:") ? String(trimmed.dropFirst(6)) : trimmed
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
