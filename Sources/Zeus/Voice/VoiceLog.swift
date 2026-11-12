import Foundation
import ZeusCore

/// One line per stage of a voice turn in ~/Library/Logs/Zeus/voice.log: wake heard, transcript,
/// route, action, spoken text, errors. Lets QA (and Tony) see where "Hey Zeus" stopped answering
/// without a debugger. Never holds audio. By default it holds metadata only: what you said and
/// what ZEUS answered are logged as a length, not as text (`logContent` below).
enum VoiceLog {
    private static let queue = DispatchQueue(label: "app.zeus.voicelog")
    static var url: URL {
        let base = ProcessInfo.processInfo.environment["ZEUS_LOG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Zeus", isDirectory: true)
        return base.appendingPathComponent("voice.log")
    }
    /// Also echoed to stdout by the offline self-test.
    nonisolated(unsafe) static var echo = false

    /// Debug only: `defaults write app.zeus.mac voice.logContent -bool YES` (or ZEUS_VOICE_LOG_CONTENT=1)
    /// puts transcripts and spoken answers in the log. Off unless set explicitly.
    static var contentLoggingEnabled: Bool {
        if ProcessInfo.processInfo.environment["ZEUS_VOICE_LOG_CONTENT"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "voice.logContent")
    }

    /// What a log line may say about a piece of conversation text.
    static func described(_ text: String, content: Bool = contentLoggingEnabled) -> String {
        VoiceLogRecord.contentDescription(text, includeContent: content)
    }

    static func format(_ date: Date, _ stage: String, _ detail: String) -> String {
        VoiceLogRecord(stage: stage, detail: detail).line(at: date)
    }

    /// Logs conversation text (a transcript, a spoken answer): metadata unless content logging is on.
    static func logContent(_ stage: String, _ text: String, prefix: String = "") {
        log(stage, prefix + described(text))
    }

    /// `mirror: false` skips the `[ZEUS] voice:` system-log line for callers that write their own (`voice-latency`).
    static func log(_ stage: String, _ detail: String = "", mirror: Bool = true) {
        let record = VoiceLogRecord(stage: stage, detail: detail)
        let line = record.line(at: Date())
        FlightRecorder.shared.record(record.stage == "error" ? "error" : "voice", record.stage, record.detail)
        if mirror { NSLog("[ZEUS] voice: %@ %@", record.stage, record.detail) }
        if echo { print(line) }
        queue.async {
            let fm = FileManager.default
            let directory = url.deletingLastPathComponent()
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if !fm.fileExists(atPath: url.path) {
                _ = fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            // Repairs a file an older build created with the default umask (also the rotated copy).
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if fm.fileExists(atPath: old.path) { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: old.path) }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        }
    }
}
