import Foundation

/// Turns a transcript into an explain command. Open and quit in production go through `FastIntent.parse` first.
public enum ExplainTranscript {
    public static func command(for text: String) -> ExplainCommand {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("open ") { return .openApp(rest(trimmed, dropping: 5)) }
        if lower.hasPrefix("quit ") { return .quitApp(rest(trimmed, dropping: 5)) }
        if lower.hasPrefix("close ") { return .quitApp(rest(trimmed, dropping: 6)) }
        if lower.contains("explain this") { return .explain }
        if let name = capture(trimmed, lower: lower, lead: "where to click to ") { return .point(name) }
        if lower.contains(" for me"), let name = between(trimmed, lower: lower, start: "click ", end: " for me") {
            return .clickForPerson(name)
        }
        if lower.contains("walk me through") { return .walk }
        if lower.contains("describe") { return .describe }
        return .none
    }

    private static func rest(_ text: String, dropping count: Int) -> String {
        String(text.dropFirst(count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(_ text: String, lower: String, lead: String) -> String? {
        guard let range = lower.range(of: lead) else { return nil }
        let name = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func between(_ text: String, lower: String, start: String, end: String) -> String? {
        guard let startRange = lower.range(of: start), let endRange = lower.range(of: end), startRange.upperBound <= endRange.lowerBound else {
            return nil
        }
        let name = String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
