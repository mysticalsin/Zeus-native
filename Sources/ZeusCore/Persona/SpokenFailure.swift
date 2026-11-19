import Foundation

/// Spoken errors stay at or under ten words. Provider text is never read aloud (R24 persona); a technical
/// error becomes an in-character line from the persona bank (`ZeusVoiceLines.Situation.errorSpoken`).
public enum SpokenFailure {
    public static func line(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ZeusVoiceLines.line(for: .errorSpoken) }
        let lowered = text.lowercased()
        if isQuota(lowered) { return "Every AI is out of quota." }
        if isProviderDump(lowered) { return ZeusVoiceLines.line(for: .errorSpoken) }
        let words = text.split(separator: " ")
        guard words.count > 10 else { return text }
        let clipped = words.prefix(10).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
        return clipped + "."
    }

    private static func isQuota(_ lowered: String) -> Bool {
        ["usage limit", "weekly limit", "hit your limit", "hit your weekly", "rate limit", "quota", "429"]
            .contains { lowered.contains($0) }
    }

    private static func isProviderDump(_ lowered: String) -> Bool {
        ["traceback", "exception", "error:", "http ", "http/", "stack trace", "brain:", "failed;", "exit code", "timed out"].contains { lowered.contains($0) }
    }
}
