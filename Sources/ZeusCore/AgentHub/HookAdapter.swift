import Foundation

/// Permissive stand-in for the hook gate. The transition tests name the session table,
/// the connection-error screen, and one finish decision. This stand-in accepts every
/// line and leaves the session where it was, so those tests fail until the gate lands.

public enum HubHookConnection: Equatable, Sendable {
    case opening
    case open
    case failed

    public static func screen(_ connection: HubHookConnection, sessionCount: Int) -> HubScreen {
        _ = (connection, sessionCount)
        return .empty
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

    public static func canAsk(_ source: HookEvent.Source) -> Bool { true }

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
    public static let maximumPathBytes = 103
    public static let maximumDepth = 32
    public static let maximumNodes = 4_096

    public static let events: Set<String> = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "AskUserQuestion", "Stop", "StopFailure",
        "SessionEnd", "AgentResponse", "Notification", "QuietForTheStallLimit",
    ]

    public static func acceptsSocketPath(_ path: String, expected: String) -> Bool {
        _ = (path, expected)
        return true
    }

    public static func admits(peer: PeerVerdict) -> Bool {
        _ = peer
        return true
    }

    public static func inspect(line: Data, peer: PeerVerdict) -> Result<HubHookMessage, HubHookRejection> {
        _ = (line, peer)
        return .success(HubHookMessage(
            source: .codex,
            event: "PermissionRequest",
            sessionID: "s1",
            tool: nil,
            command: nil,
            needsDecision: true,
            autoApproves: false
        ))
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

    public var screen: HubScreen { .empty }

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
        _ = (now, systemFinishSound)
        let current = sessions[message.sessionID] ?? HubSessionState()
        let finish = message.event == "Stop"
        let decision = HubSoundDecision(status: .silent, cues: [.done])
        return HubHookStep(
            state: current,
            growsApprove: message.event == "PermissionRequest" || message.needsDecision,
            soundDecisions: finish ? [decision, decision] : [],
            playsExtraFinishSound: finish
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

    @discardableResult
    public mutating func resolve(
        sessionID: String,
        verdict: HookDecision.Verdict,
        timedOut: Bool = false,
        now: Date
    ) -> HubHookStep {
        _ = (verdict, timedOut, now)
        let current = sessions[sessionID] ?? HubSessionState()
        return HubHookStep(
            state: current,
            growsApprove: false,
            soundDecisions: [],
            playsExtraFinishSound: false
        )
    }
}
