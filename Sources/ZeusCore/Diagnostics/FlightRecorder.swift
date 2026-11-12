import Foundation

/// One thing that happened in the app: a voice stage, a notch cue, an agent event, an error.
public struct RecordedEvent: Equatable, Codable, Sendable {
    public var date: Date
    public var source: String
    public var stage: String
    public var detail: String
    public init(date: Date, source: String, stage: String, detail: String) {
        self.date = date; self.source = source; self.stage = stage; self.detail = detail
    }
}

/// Takes secrets out of text before it is kept or exported: API keys, bearer tokens, `token=...` pairs, JWTs,
/// long hex strings, and the home folder name.
public enum DiagnosticsRedactor {
    public static let mask = "[redacted]"

    private static let patterns: [(NSRegularExpression, String)] = {
        func rx(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
        return [
            // key = value pairs keep the key so the log still reads
            (rx("(?i)\\b(api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|token|secret|password|passwd|authorization|license[_-]?key|licence)([\"']?\\s*[:=]\\s*[\"']?)(Bearer\\s+)?[^\\s\"',;&}]+"), "$1$2" + mask),
            (rx("(?i)\\bbearer\\s+[A-Za-z0-9._~+/=\\-]{8,}"), "Bearer " + mask),
            (rx("\\bsk-[A-Za-z0-9_\\-]{12,}"), mask),
            (rx("\\b(?:ghp|gho|ghs|github_pat|xox[abprs]|AIza|AKIA)[A-Za-z0-9_\\-]{10,}"), mask),
            (rx("\\beyJ[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}\\.[A-Za-z0-9_\\-]{5,}"), mask),
            (rx("\\b[A-Fa-f0-9]{32,}\\b"), mask),
        ]
    }()

    public static func redact(_ text: String, home: String = NSHomeDirectory()) -> String {
        var out = text
        for (regex, template) in patterns {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        if home.count > 1 { out = out.replacingOccurrences(of: home, with: "~") }
        return out
    }

    /// Settings ids whose value is a secret whatever it looks like.
    public static func isSecretKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return ["key", "token", "secret", "password", "licen", "auth", "credential"].contains { lower.contains($0) }
            && !lower.hasSuffix("shortcut") && !lower.contains("keyboard") && !lower.contains("hotkey") && !lower.contains("talkkey") && !lower.contains("dictation.key")
    }

    /// A settings snapshot with secret values masked and every string run through `redact`.
    public static func redactSettings(_ value: Any, key: String = "") -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { $0[$1.key] = redactSettings($1.value, key: $1.key) }
        }
        if let array = value as? [Any] { return array.map { redactSettings($0, key: key) } }
        if let string = value as? String {
            if isSecretKey(key), !string.isEmpty { return mask }
            return redact(string)
        }
        return value
    }
}

/// A ring of the last `capacity` app events, kept in memory so a bug report can say what just happened
/// without anyone having turned logging on. Detail text is redacted as it goes in.
public final class FlightRecorder: @unchecked Sendable {
    public static let defaultCapacity = 2000
    public static let shared = FlightRecorder()

    public let capacity: Int
    private let lock = NSLock()
    private var ring: [RecordedEvent?]
    private var next = 0
    private var total = 0

    public init(capacity: Int = FlightRecorder.defaultCapacity) {
        self.capacity = max(1, capacity)
        ring = Array(repeating: nil, count: max(1, capacity))
    }

    public func record(_ source: String, _ stage: String, _ detail: String = "", at date: Date = Date()) {
        let event = RecordedEvent(date: date, source: source, stage: stage,
                                  detail: DiagnosticsRedactor.redact(detail.replacingOccurrences(of: "\n", with: " ")))
        lock.lock(); defer { lock.unlock() }
        ring[next] = event
        next = (next + 1) % capacity
        total += 1
    }

    /// Oldest first.
    public var events: [RecordedEvent] {
        lock.lock(); defer { lock.unlock() }
        let count = min(total, capacity)
        let start = total > capacity ? next : 0
        return (0..<count).compactMap { ring[(start + $0) % capacity] }
    }

    /// Everything ever recorded, including events the ring has since dropped.
    public var totalRecorded: Int { lock.lock(); defer { lock.unlock() }; return total }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        ring = Array(repeating: nil, count: capacity); next = 0; total = 0
    }

    public static func line(_ event: RecordedEvent) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(formatter.string(from: event.date)) \(event.source.padding(toLength: 8, withPad: " ", startingAt: 0)) \(event.stage.padding(toLength: 12, withPad: " ", startingAt: 0)) \(event.detail)"
    }

    public func text() -> String { events.map(Self.line).joined(separator: "\n") + "\n" }
}

/// What "Export diagnostics" writes next to the zip's contents.
public struct DiagnosticsManifest: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public var path: String
        public var bytes: Int
    }
    public var app: String
    public var version: String
    public var build: String
    public var created: Date
    public var os: String
    public var eventCount: Int
    public var secretsRedacted: Bool
    public var files: [File]

    public init(app: String = "Zeus", version: String, build: String, created: Date, os: String, eventCount: Int, files: [File]) {
        self.app = app; self.version = version; self.build = build; self.created = created; self.os = os
        self.eventCount = eventCount; secretsRedacted = true; self.files = files
    }
}

public enum DiagnosticsExporter {
    public struct Input: Sendable {
        public var version: String
        public var build: String
        public var settingsJSON: Data
        public var logFiles: [URL]
        public var recorder: FlightRecorder
        public var now: Date
        public init(version: String, build: String, settingsJSON: Data, logFiles: [URL], recorder: FlightRecorder = .shared, now: Date = Date()) {
            self.version = version; self.build = build; self.settingsJSON = settingsJSON; self.logFiles = logFiles; self.recorder = recorder; self.now = now
        }
    }

    public static func zipName(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Zeus-diagnostics-\(formatter.string(from: now)).zip"
    }

    /// Builds the folder that gets zipped: logs (redacted), the flight recorder, settings (secrets masked),
    /// version.txt and manifest.json. Returns the manifest it wrote.
    @discardableResult
    public static func stage(_ input: Input, in folder: URL) throws -> DiagnosticsManifest {
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("logs"), withIntermediateDirectories: true)
        var files: [DiagnosticsManifest.File] = []
        func write(_ data: Data, _ path: String) throws {
            try data.write(to: folder.appendingPathComponent(path))
            files.append(.init(path: path, bytes: data.count))
        }
        for url in input.logFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            try write(Data(DiagnosticsRedactor.redact(text).utf8), "logs/" + url.lastPathComponent)
        }
        try write(Data(input.recorder.text().utf8), "logs/flight-recorder.log")
        if let object = try? JSONSerialization.jsonObject(with: input.settingsJSON) {
            let redacted = DiagnosticsRedactor.redactSettings(object)
            try write(try JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]), "settings.json")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        try write(Data("Zeus \(input.version) (build \(input.build))\nmacOS \(os)\n".utf8), "version.txt")
        let manifest = DiagnosticsManifest(version: input.version, build: input.build, created: input.now, os: os,
                                           eventCount: input.recorder.events.count, files: files.sorted { $0.path < $1.path })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return manifest
    }

    /// Stages and zips into `destination` (a folder). Returns the zip.
    public static func export(_ input: Input, to destination: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("zeus-diagnostics-\(UUID().uuidString)/Zeus-diagnostics", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }
        try stage(input, in: staging)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let zip = destination.appendingPathComponent(zipName(now: input.now))
        try? fm.removeItem(at: zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", staging.path, zip.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }
}
