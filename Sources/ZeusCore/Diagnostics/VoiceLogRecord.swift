import Foundation

/// One sanitized value shared by every voice diagnostic sink. Conversation text must
/// pass through contentDescription first; opting into content never opts out of redaction.
public struct VoiceLogRecord: Sendable, Equatable {
    public let stage: String
    public let detail: String

    public init(stage: String, detail: String, home: String = NSHomeDirectory()) {
        self.stage = Self.field(stage, byteLimit: 160, home: home)
        self.detail = Self.field(detail, byteLimit: 8_192, home: home)
    }

    public static func contentDescription(_ text: String, includeContent: Bool) -> String {
        includeContent ? text : "(\(text.count) chars)"
    }

    public func line(at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(formatter.string(from: date)) \(stage.padding(toLength: 10, withPad: " ", startingAt: 0)) \(detail)"
    }

    private static func field(_ text: String, byteLimit: Int, home: String) -> String {
        // Do not run regexes over an arbitrarily large provider response, or truncate a
        // credential into a prefix that no longer matches its redaction pattern.
        guard text.utf8.count <= byteLimit else { return "[oversized diagnostic omitted]" }
        let redacted = DiagnosticsRedactor.redact(text, home: home)
        let flattened = redacted.components(separatedBy: .newlines).joined(separator: " ")
        return flattened.utf8.count <= byteLimit ? flattened : "[oversized diagnostic omitted]"
    }
}
