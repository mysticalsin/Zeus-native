import Foundation

public struct MeetingTranscriptLine: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var speaker: String
    public var text: String
}

public struct MeetingTranscript: Codable, Equatable, Sendable {
    public var lines: [MeetingTranscriptLine]

    public func text() -> String {
        lines.map { "[\(format($0.start))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    public func answer(question: String) -> String {
        let words = Set(question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 3 })
        let scored = lines.map { line -> (MeetingTranscriptLine, Int) in
            let lineWords = Set(line.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (line, lineWords.intersection(words).count)
        }.sorted { $0.1 > $1.1 }
        if let best = scored.first, best.1 > 0 { return best.0.text }
        return "Nothing about that in this call."
    }
}

public enum MeetingCopilotEngine {
    /// Reads a fixture file (JSON lines or SRT-like text). No microphone and no saved audio.
    public static func transcribeFixture(at url: URL) throws -> MeetingTranscript {
        let raw = try String(contentsOf: url, encoding: .utf8)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") || raw.contains("\"speaker\"") {
            let data = Data(raw.utf8)
            if let lines = try? JSONDecoder().decode([MeetingTranscriptLine].self, from: data) {
                return MeetingTranscript(lines: lines)
            }
        }
        var lines: [MeetingTranscriptLine] = []
        var index = 0
        for row in raw.split(separator: "\n") {
            let text = String(row)
            if text.isEmpty { continue }
            lines.append(MeetingTranscriptLine(start: TimeInterval(index * 5), speaker: index.isMultiple(of: 2) ? "Them" : "You", text: text))
            index += 1
        }
        return MeetingTranscript(lines: lines)
    }
}

public struct MeetingArchive: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public struct Event: Codable, Equatable, Sendable {
        public var date: Date
        public var kind: String
        public var detail: String

        public init(date: Date, kind: String, detail: String) {
            self.date = date
            self.kind = kind
            self.detail = detail
        }
    }

    public func append(_ event: Event) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(event) + Data("\n".utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum MeetingPanelVisibility {
    /// Hidden from screen share unless the person turned on "Show in screen sharing" (lane N).
    public static func isHiddenFromCapture(meetingActive: Bool, showInScreenShare: Bool) -> Bool {
        meetingActive && !showInScreenShare
    }
}
