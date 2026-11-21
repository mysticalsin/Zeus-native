import Foundation

/// Turns one hook line into a session step. The socket is a local trust boundary:
/// every line is bounded, a bad line changes nothing, and a family that cannot ask
/// never grows Approve. This type does not bind a socket and does not play a sound.

public enum HubHookConnection: Equatable, Sendable {
    case opening
    case open
    case failed

    /// A failed socket is the connection-error screen, including when rows are still stored.
    /// The empty sentence is only an open socket with no sessions.
    public static func screen(_ connection: HubHookConnection, sessionCount: Int) -> HubScreen {
        switch connection {
        case .failed:
            return .connectionError
        case .opening:
            return .loading
        case .open:
            return sessionCount == 0 ? .empty : .ready
        }
    }
}

public enum HubHookRejection: Equatable, Sendable {
    case oversized
    case malformed
    case unknownEvent
    case unknownSource
    case unboundedField
    case peerDenied
}

public struct HubHookMessage: Equatable, Sendable {
    public var source: HookEvent.Source
    public var event: String
    public var sessionID: String
    public var tool: String?
    public var command: String?
    public var needsDecision: Bool
    /// Set by the app from its own trust store. A line cannot turn this on.
    public var autoApproves: Bool

    public init(
        source: HookEvent.Source,
        event: String,
        sessionID: String,
        tool: String?,
        command: String?,
        needsDecision: Bool,
        autoApproves: Bool
    ) {
        self.source = source
        self.event = event
        self.sessionID = sessionID
        self.tool = tool
        self.command = command
        self.needsDecision = needsDecision
        self.autoApproves = autoApproves
    }
}

public struct HubHookStep: Equatable, Sendable {
    public var state: HubSessionState
    public var growsApprove: Bool
    public var soundDecisions: [HubSoundDecision]
    public var playsExtraFinishSound: Bool
    public var rejection: HubHookRejection?

    public init(
        state: HubSessionState,
        growsApprove: Bool,
        soundDecisions: [HubSoundDecision],
        playsExtraFinishSound: Bool,
        rejection: HubHookRejection? = nil
    ) {
        self.state = state
        self.growsApprove = growsApprove
        self.soundDecisions = soundDecisions
        self.playsExtraFinishSound = playsExtraFinishSound
        self.rejection = rejection
    }
}

public enum HubHookFamily {
    public static let askingSources: [HookEvent.Source] = [.claudeCode, .codex]
    public static let observingSources: [HookEvent.Source] = [.gemini, .cursor]

    /// A family that waits for a decision. The line's own flag is not consulted.
    public static func canAsk(_ source: HookEvent.Source) -> Bool {
        switch source {
        case .claudeCode, .codex:
            return true
        case .cursor, .gemini:
            return false
        }
    }

    public static func isQuestion(event: String, tool: String?) -> Bool {
        event == "AskUserQuestion" || tool == "AskUserQuestion"
    }
}

public enum HubHookGate {
    public static let maximumMessageBytes = UnixSocket.maximumMessageBytes
    public static let maximumIdentifierBytes = 256
    public static let maximumEventBytes = 64
    public static let maximumToolBytes = 128
    public static let maximumDetailBytes = 8_192
    public static let maximumCommandBytes = 4_096
    public static let maximumPathFieldBytes = 1_024
    /// `sockaddr_un.sun_path` holds 104 bytes, including the trailing NUL.
    public static let maximumPathBytes = 103
    public static let maximumDepth = 32
    public static let maximumNodes = 4_096

    public static let events: Set<String> = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "AskUserQuestion", "Stop", "StopFailure",
        "SessionEnd", "AgentResponse", "Notification", "QuietForTheStallLimit",
    ]

    /// The path the server is about to bind. It must be the path the app chose,
    /// absolute, free of empty and parent components, and short enough to bind.
    public static func acceptsSocketPath(_ path: String, expected: String) -> Bool {
        guard path == expected else { return false }
        guard (1...maximumPathBytes).contains(path.utf8.count) else { return false }
        guard !path.utf8.contains(0) else { return false }
        guard path.hasPrefix("/") else { return false }
        guard !path.contains("//") else { return false }
        let parts = path.split(separator: "/")
        guard !parts.isEmpty else { return false }
        for part in parts where part == "." || part == ".." {
            return false
        }
        return true
    }

    public static func admits(peer: PeerVerdict) -> Bool {
        peer == .allow
    }

    /// Reads a line only after the peer is allowed. A rejection carries no field from the line.
    public static func inspect(line: Data, peer: PeerVerdict) -> Result<HubHookMessage, HubHookRejection> {
        guard admits(peer: peer) else { return .failure(.peerDenied) }
        guard line.count <= maximumMessageBytes else { return .failure(.oversized) }
        switch scan(line) {
        case .malformed:
            return .failure(.malformed)
        case .tooDeep:
            return .failure(.unboundedField)
        case .ok:
            break
        }
        guard let root = try? JSONSerialization.jsonObject(with: line) else { return .failure(.malformed) }
        var nodes = 0
        guard within(root, depth: 1, nodes: &nodes) else { return .failure(.unboundedField) }
        guard root is [String: Any] else { return .failure(.malformed) }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: line)
        } catch {
            return .failure(.malformed)
        }
        guard envelope.v == 1 else { return .failure(.malformed) }
        guard let source = HookEvent.Source(rawValue: envelope.source) else { return .failure(.unknownSource) }
        guard let sessionID = envelope.session, !sessionID.isEmpty else { return .failure(.malformed) }
        guard boundedIdentifier(envelope.id), boundedIdentifier(sessionID) else { return .failure(.unboundedField) }
        guard !envelope.event.isEmpty else { return .failure(.malformed) }
        guard envelope.event.utf8.count <= maximumEventBytes, isEventToken(envelope.event) else {
            return .failure(.unboundedField)
        }
        guard events.contains(envelope.event) else { return .failure(.unknownEvent) }
        if let tool = envelope.tool {
            guard tool.utf8.count <= maximumToolBytes, !containsControl(tool) else { return .failure(.unboundedField) }
        }
        if let detail = envelope.detail {
            guard detail.utf8.count <= maximumDetailBytes, !containsHardControl(detail) else {
                return .failure(.unboundedField)
            }
        }
        if let cwd = envelope.cwd {
            guard cwd.utf8.count <= maximumPathFieldBytes, !containsControl(cwd) else {
                return .failure(.unboundedField)
            }
        }
        let command: String?
        if let text = envelope.input?["command"]?.stringValue {
            guard text.utf8.count <= maximumCommandBytes, !containsHardControl(text) else {
                return .failure(.unboundedField)
            }
            command = text
        } else {
            command = nil
        }
        return .success(HubHookMessage(
            source: source,
            event: envelope.event,
            sessionID: sessionID,
            tool: envelope.tool,
            command: command,
            needsDecision: envelope.needsDecision,
            autoApproves: false
        ))
    }

    private struct Envelope: Decodable {
        var v: Int
        var id: String
        var source: String
        var event: String
        var session: String?
        var cwd: String?
        var tool: String?
        var input: JSONValue?
        var detail: String?
        var needsDecision: Bool
    }

    private enum Scan {
        case ok
        case malformed
        case tooDeep
    }

    /// Counts brackets outside strings so a deep line is refused before the parser walks it.
    private static func scan(_ data: Data) -> Scan {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if byte == 0 { return .malformed }
            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if byte == 0x5C {
                    escaped = true
                    continue
                }
                if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22:
                inString = true
            case 0x7B, 0x5B:
                depth += 1
                if depth > maximumDepth { return .tooDeep }
            case 0x7D, 0x5D:
                depth -= 1
                if depth < 0 { return .malformed }
            default:
                break
            }
        }
        if inString || depth != 0 { return .malformed }
        return .ok
    }

    private static func within(_ value: Any, depth: Int, nodes: inout Int) -> Bool {
        nodes += 1
        if nodes > maximumNodes || depth > maximumDepth { return false }
        if let array = value as? [Any] {
            for item in array where !within(item, depth: depth + 1, nodes: &nodes) {
                return false
            }
        } else if let object = value as? [String: Any] {
            for item in object.values where !within(item, depth: depth + 1, nodes: &nodes) {
                return false
            }
        }
        return true
    }

    private static func boundedIdentifier(_ text: String) -> Bool {
        (1...maximumIdentifierBytes).contains(text.utf8.count) && !containsControl(text)
    }

    private static func isEventToken(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || (value >= 48 && value <= 57)
        }
    }

    private static func containsControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// Detail and command text may keep tabs and line breaks. Every other control is refused.
    private static func containsHardControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value == 0x09 || value == 0x0A || value == 0x0D { return false }
            return value < 0x20 || value == 0x7F
        }
    }
}

public struct HubHookBook: Sendable {
    public private(set) var sessions: [String: HubSessionState]
    public private(set) var connection: HubHookConnection
    public private(set) var sound: HubSound

    public init(sessions: [String: HubSessionState] = [:], connection: HubHookConnection = .failed) {
        self.sessions = sessions
        self.connection = connection
        self.sound = HubSound()
    }

    public var screen: HubScreen {
        HubHookConnection.screen(connection, sessionCount: sessions.count)
    }

    public mutating func beginOpening() { connection = .opening }

    public mutating func open() { connection = .open }

    public mutating func fail() { connection = .failed }

    public mutating func optIn() { _ = sound.apply(.optIn) }

    public mutating func optOut() { _ = sound.apply(.optOut) }

    @discardableResult
    public mutating func apply(
        _ message: HubHookMessage,
        now: Date,
        systemFinishSound: Bool = false
    ) -> HubHookStep {
        let current = sessions[message.sessionID] ?? HubSessionState()
        let mapped = Self.sessionEvent(message, status: current.status)
        let next = mapped.map { HubSessionMachine.next(current, $0) } ?? current
        if Self.isLive(next.status), !Self.isLive(current.status) {
            _ = sound.session(message.sessionID, status: .working, at: now, startEnabled: false)
        }
        let decisions = finishDecisions(message, at: now, systemFinishSound: systemFinishSound)
        if next.status == .absent {
            sessions.removeValue(forKey: message.sessionID)
        } else {
            sessions[message.sessionID] = next
        }
        return HubHookStep(
            state: next,
            growsApprove: Self.growsApprove(message, before: current, after: next),
            soundDecisions: decisions,
            playsExtraFinishSound: false
        )
    }

    @discardableResult
    public mutating func receive(
        line: Data,
        peer: PeerVerdict,
        now: Date,
        systemFinishSound: Bool = false
    ) -> HubHookStep {
        switch HubHookGate.inspect(line: line, peer: peer) {
        case .failure(let rejection):
            return HubHookStep(
                state: HubSessionState(),
                growsApprove: false,
                soundDecisions: [],
                playsExtraFinishSound: false,
                rejection: rejection
            )
        case .success(let message):
            return apply(message, now: now, systemFinishSound: systemFinishSound)
        }
    }

    /// Ask resolves like an approval: the stored previous state, not a new approval.
    /// Timeout uses the deny path on the session table.
    @discardableResult
    public mutating func resolve(
        sessionID: String,
        verdict: HookDecision.Verdict,
        timedOut: Bool = false,
        now: Date
    ) -> HubHookStep {
        _ = now
        let current = sessions[sessionID] ?? HubSessionState()
        let event: HubSessionEvent = if timedOut {
            .timedOut
        } else {
            switch verdict {
            case .allow, .ask: .approved
            case .deny: .denied
            }
        }
        let next = HubSessionMachine.next(current, event)
        if next.status == .absent {
            sessions.removeValue(forKey: sessionID)
        } else {
            sessions[sessionID] = next
        }
        return HubHookStep(
            state: next,
            growsApprove: false,
            soundDecisions: [],
            playsExtraFinishSound: false
        )
    }

    /// One Stop is one decision. `systemFinishSound` does not add a cue, and nothing here plays one.
    private mutating func finishDecisions(
        _ message: HubHookMessage,
        at now: Date,
        systemFinishSound: Bool
    ) -> [HubSoundDecision] {
        guard message.event == "Stop" else { return [] }
        let decision = sound.finish(
            message.sessionID,
            at: now,
            startEnabled: false,
            systemFinishSound: systemFinishSound
        )
        return [HubSoundDecision(status: decision.status, cues: Array(decision.cues.prefix(1)))]
    }

    private static func isLive(_ status: HubSessionStatus) -> Bool {
        switch status {
        case .running, .waitingForInput, .needsApproval:
            return true
        case .absent, .loading, .done, .error:
            return false
        }
    }

    private static func growsApprove(_ message: HubHookMessage, before: HubSessionState, after: HubSessionState) -> Bool {
        let question = HubHookFamily.isQuestion(event: message.event, tool: message.tool)
        let blocked = message.command.flatMap(HandsBlocklist.reason) != nil
        return message.event == "PermissionRequest"
            && HubHookFamily.canAsk(message.source)
            && !question
            && !message.autoApproves
            && !blocked
            && before.status != .needsApproval
            && after.status == .needsApproval
    }

    /// Quiet tool, question, and permission lines are activity, so the stall clears and Approve does not.
    private static func sessionEvent(_ message: HubHookMessage, status: HubSessionStatus) -> HubSessionEvent? {
        if let command = message.command, HandsBlocklist.reason(command) != nil,
           message.event == "PermissionRequest" || message.event == "PreToolUse" || message.event == "PostToolUse" {
            return .failed
        }
        let question = HubHookFamily.isQuestion(event: message.event, tool: message.tool)
        let capable = HubHookFamily.canAsk(message.source)
        let quiet = status == .error(.quiet)
        switch message.event {
        case "SessionStart":
            return .announced
        case "UserPromptSubmit":
            return .promptStarted
        case "PreToolUse":
            return quiet ? .activity : .toolActivity
        case "PostToolUse":
            if question, status == .waitingForInput { return .answerAccepted }
            return quiet ? .activity : .toolActivity
        case "PermissionRequest":
            if message.autoApproves, !question { return quiet ? .activity : .toolActivity }
            if question { return quiet ? .activity : .questionAsked }
            if capable { return quiet ? .activity : .approvalRequested }
            return quiet ? .activity : .toolActivity
        case "AskUserQuestion":
            return quiet ? .activity : .questionAsked
        case "Stop":
            return .finished
        case "StopFailure":
            return .failed
        case "SessionEnd":
            return .ended
        case "QuietForTheStallLimit":
            return .quietForTheStallLimit
        case "AgentResponse", "Notification":
            return nil
        default:
            return nil
        }
    }
}
