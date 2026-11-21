import Foundation

/// Stages of one talk turn, measured from key release. The raw values are the only stage names
/// written to the local trace. No transcript, answer, or other text is stored.
public enum ActionSpeedStage: String, Codable, CaseIterable, Sendable {
    case keyRelease
    case sttFinal
    case requestSent
    case firstModelToken
    case firstToolDecision
    case firstTtsAudio
    case firstOverlayPaint
    case pointerArrival
}

/// One stage mark. `turn` is a UUID. `monoNs` is a monotonic clock, not wall time.
public struct ActionSpeedEvent: Equatable, Sendable {
    public var turn: String
    public var stage: ActionSpeedStage
    public var monoNs: Int64

    public init(turn: String, stage: ActionSpeedStage, monoNs: Int64) {
        self.turn = turn
        self.stage = stage
        self.monoNs = monoNs
    }

    /// One JSON object. The keys are exactly `turn`, `stage`, and `monoNs`.
    public func jsonLine() -> String {
        "{\"turn\":\"\(turn)\",\"stage\":\"\(stage.rawValue)\",\"monoNs\":\(monoNs)}"
    }
}

/// Monotonic nanoseconds since this process first read the clock. Not wall time.
public enum ActionSpeedClock {
    private static let origin = ContinuousClock.now

    public static func nanoseconds(now: ContinuousClock.Instant = .now) -> Int64 {
        let duration = now - origin
        let seconds = duration.components.seconds
        let nanos = duration.components.attoseconds / 1_000_000_000
        return seconds * 1_000_000_000 + nanos
    }
}

/// In-memory stage trace. Disk writes happen only when `enabled` is true and `file` is set.
/// The debug flag is off unless `ZEUS_ACTION_SPEED_TRACE` is `1`.
public struct ActionSpeedTrace: Equatable, Sendable {
    public static let enableEnvironment = "ZEUS_ACTION_SPEED_TRACE"
    public static let fileEnvironment = "ZEUS_ACTION_SPEED_TRACE_FILE"
    public static let maxEvents = 4_096

    public var enabled: Bool
    public var file: URL?
    public private(set) var events: [ActionSpeedEvent] = []
    public private(set) var activeTurn: String?

    public init(enabled: Bool = false, file: URL? = nil) {
        self.enabled = enabled
        self.file = file
    }

    /// Off unless the flag is exactly `1`. A file path is ignored while the flag is off,
    /// so a leftover path cannot write a trace.
    public static func configured(_ environment: [String: String], home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> ActionSpeedTrace {
        guard environment[enableEnvironment] == "1" else { return ActionSpeedTrace(enabled: false, file: nil) }
        if let path = environment[fileEnvironment], !path.isEmpty {
            return ActionSpeedTrace(enabled: true, file: URL(fileURLWithPath: path))
        }
        return ActionSpeedTrace(enabled: true, file: supportFile(home: home))
    }

    public static func supportFile(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Zeus/action-speed.jsonl")
    }

    public static func turnID(_ text: String) -> String? {
        guard let id = UUID(uuidString: text) else { return nil }
        return id.uuidString
    }

    /// Starts a turn and marks key release. Nil when tracing is off or `id` is not a UUID.
    @discardableResult
    public mutating func beginTurn(id: String = UUID().uuidString, monoNs: Int64) -> String? {
        guard enabled, let turn = Self.turnID(id) else { return nil }
        activeTurn = turn
        record(.keyRelease, turn: turn, monoNs: monoNs)
        return turn
    }

    /// The first mark for a stage on the active turn wins. Later marks for that stage are dropped.
    public mutating func mark(_ stage: ActionSpeedStage, monoNs: Int64) {
        guard enabled, let turn = activeTurn else { return }
        record(stage, turn: turn, monoNs: monoNs)
    }

    public func offsetMs(_ stage: ActionSpeedStage, turn: String) -> Int? {
        guard let key = events.first(where: { $0.turn == turn && $0.stage == .keyRelease })?.monoNs,
              let mark = events.first(where: { $0.turn == turn && $0.stage == stage })?.monoNs else { return nil }
        return Int(max(0, mark - key) / 1_000_000)
    }

    /// Stage durations for the merged talk clock. Capture is absent. Nil until speech-to-text,
    /// the first token, and the first audio buffer have all been marked.
    public func talkSample(turn: String) -> TalkLatencySample? {
        guard let stt = offsetMs(.sttFinal, turn: turn),
              let token = offsetMs(.firstModelToken, turn: turn),
              let audio = offsetMs(.firstTtsAudio, turn: turn) else { return nil }
        let tokenSpan = token - stt
        let audioSpan = audio - token
        return TalkLatencySample(sttFinalMs: stt, firstTokenMs: tokenSpan, ttsFirstMs: audioSpan,
                                 firstVisualMs: offsetMs(.firstOverlayPaint, turn: turn))
    }

    private mutating func record(_ stage: ActionSpeedStage, turn: String, monoNs: Int64) {
        guard !events.contains(where: { $0.turn == turn && $0.stage == stage }) else { return }
        let event = ActionSpeedEvent(turn: turn, stage: stage, monoNs: monoNs)
        events.append(event)
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        if let file {
            try? ActionSpeedSink.appendLine(event.jsonLine(), to: file)
        }
    }
}

/// Appends one JSON line. Creates the parent directory at mode 0700 and the file at mode 0600.
public enum ActionSpeedSink {
    public static func appendLine(_ line: String, to url: URL) throws {
        guard !line.isEmpty, !line.contains("\n") else { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Process-wide trace. `beginTurn` and `mark` do nothing on disk unless the debug flag is on.
public final class ActionSpeedLog: @unchecked Sendable {
    public static let shared = ActionSpeedLog()

    private let lock = NSLock()
    private var trace = ActionSpeedTrace()
    private var didBootstrap = false

    public func beginTurn() -> String {
        bootstrapIfNeeded()
        let id = UUID().uuidString
        let now = ActionSpeedClock.nanoseconds()
        lock.lock()
        _ = trace.beginTurn(id: id, monoNs: now)
        lock.unlock()
        return id
    }

    /// Starts a turn only when tracing is on and no turn is open. A key release that already began one is left as it is.
    public func ensureTurn() {
        bootstrapIfNeeded()
        lock.lock()
        let needs = trace.enabled && trace.activeTurn == nil
        lock.unlock()
        if needs { _ = beginTurn() }
    }

    public func mark(_ stage: ActionSpeedStage) {
        bootstrapIfNeeded()
        let now = ActionSpeedClock.nanoseconds()
        lock.lock()
        trace.mark(stage, monoNs: now)
        lock.unlock()
    }

    private func bootstrapIfNeeded() {
        lock.lock()
        let ready = didBootstrap
        lock.unlock()
        guard !ready else { return }
        let configured = ActionSpeedTrace.configured(ProcessInfo.processInfo.environment)
        lock.lock()
        if !didBootstrap {
            trace = configured
            didBootstrap = true
        }
        lock.unlock()
    }
}
