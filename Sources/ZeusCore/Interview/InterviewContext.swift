import Foundation

/// Local notes for an interview. They stay on this Mac. Nothing here records a call or sends the text.
public enum InterviewContext {
    public static let storageKey = "opt.interview.context"
    public static let limit = 2000

    public static func normalize(_ stored: String?) -> String {
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }
}
