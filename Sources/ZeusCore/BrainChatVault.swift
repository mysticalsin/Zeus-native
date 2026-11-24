import Foundation

/// One finished chat line that may be written into the selected vault inbox.
public struct BrainChatLine: Equatable, Sendable {
    public var record: String
    public var role: String
    public var text: String
    public var failed: Bool
    public var created: Date

    public init(record: String, role: String, text: String, failed: Bool, created: Date) {
        self.record = record
        self.role = role
        self.text = text
        self.failed = failed
        self.created = created
    }
}

/// What a send did with each line. Tokens are the safe record ids that were kept.
public struct BrainChatSendResult: Equatable, Sendable {
    public var written: [String]
    public var refreshed: [String]
    public var unchanged: [String]
    public var skipped: [String]

    public init(written: [String] = [], refreshed: [String] = [], unchanged: [String] = [], skipped: [String] = []) {
        self.written = written
        self.refreshed = refreshed
        self.unchanged = unchanged
        self.skipped = skipped
    }
}

/// Writes finished chat lines into one inbox. The file name is `zeus-chat-` plus a safe record token.
/// An empty line, a failed line, or an unsafe id is skipped. A symlink is not followed. A file that is
/// not already this record is left untouched. The same bytes are not written again.
public enum BrainChatVault {
    public static func send(title: String, lines: [BrainChatLine], inbox: URL,
                             timeZone: TimeZone = .current) -> BrainChatSendResult {
        var result = BrainChatSendResult()
        for line in lines {
            switch place(title: title, line: line, inbox: inbox, timeZone: timeZone) {
            case .written(let token): result.written.append(token)
            case .refreshed(let token): result.refreshed.append(token)
            case .unchanged(let token): result.unchanged.append(token)
            case .skipped: result.skipped.append(line.record)
            }
        }
        return result
    }

    private enum Place {
        case written(String)
        case refreshed(String)
        case unchanged(String)
        case skipped
    }

    private static func place(title: String, line: BrainChatLine, inbox: URL, timeZone: TimeZone) -> Place {
        let body = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.failed, !body.isEmpty, let token = BrainCaptureNote.token(line.record) else { return .skipped }
        let name = "zeus-chat-\(token).md"
        let target = inbox.appendingPathComponent(name)
        guard VaultPathBoundary.relativePath(of: target, in: inbox) == name else { return .skipped }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil { return .skipped }

        var note = BrainCaptureNote.document(title: title, body: body, source: "chat", created: line.created,
                                              timeZone: timeZone, record: token)
        if let role = BrainCaptureNote.token(line.role),
           let recordLine = note.range(of: "record: \(token)\n") {
            note.insert(contentsOf: "role: \(role)\n", at: recordLine.upperBound)
        }
        let data = Data(note.utf8)

        if let existing = try? Data(contentsOf: target) {
            if existing == data { return .unchanged(token) }
            guard let text = String(data: existing, encoding: .utf8), owns(text, token: token) else { return .skipped }
            do {
                try data.write(to: target, options: .atomic)
                return .refreshed(token)
            } catch {
                return .skipped
            }
        }

        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            guard VaultPathBoundary.relativePath(of: target, in: inbox) == name else { return .skipped }
            try data.write(to: target, options: .withoutOverwriting)
            return .written(token)
        } catch {
            return .skipped
        }
    }

    /// True only when this token is its own front-matter line, not a mention in the body.
    private static func owns(_ text: String, token: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else { return false }
        return lines[1..<close].contains("record: \(token)")
    }
}
