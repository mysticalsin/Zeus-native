import Foundation

/// Decides whether a typed reply may leave the hub. The app target cannot be built on Linux,
/// so the keystroke decision lives here and `AgentHub` only types a `typeLine` step.
/// Trust is forwarded to the reply machine and is not read. A destination that cannot take
/// text never asks. A line that cannot be embedded never asks and is never returned.
public struct HubReplyDispatch: Equatable, Sendable {
    public private(set) var state: HubReplyState
    public private(set) var boundSessionID: String?

    public init(state: HubReplyState = HubReplyState(), boundSessionID: String? = nil) {
        self.state = state
        self.boundSessionID = boundSessionID
    }

    /// `typeLine` is the only step that may be typed. It carries the cleaned line, never a script.
    public enum Step: Equatable, Sendable {
        case hold(HubReplyState)
        case askInline(HubReplyState)
        case typeLine(sessionID: String, line: String, state: HubReplyState)

        public var state: HubReplyState {
            switch self {
            case .hold(let state), .askInline(let state), .typeLine(_, _, let state):
                state
            }
        }

        public var typedLine: String? {
            if case .typeLine(_, let line, _) = self { return line }
            return nil
        }

        public var sessionID: String? {
            if case .typeLine(let sessionID, _, _) = self { return sessionID }
            return nil
        }

        public var asksInline: Bool {
            if case .askInline = self { return true }
            return false
        }
    }

    /// Binds the gate to the selected row. A pending approval is dropped and nothing is typed.
    /// A line that was already released is marked failed and is not returned again.
    public mutating func bind(_ sessionID: String?) -> Step {
        if sessionID == boundSessionID { return .hold(state) }
        if state.status == .awaitingDecision {
            _ = absorb(HubDecision.reply(state, .cancel))
        } else if state.status == .sending {
            _ = absorb(HubDecision.reply(state, .scriptFailed))
        }
        boundSessionID = sessionID
        return .hold(state)
    }

    public mutating func perform(
        _ event: HubReplyEvent,
        sessionID: String,
        field: String,
        destinationCanTakeText: Bool,
        trusted: Bool
    ) -> Step {
        guard sessionID == boundSessionID, !sessionID.isEmpty else { return .hold(state) }
        let context = HubReplyContext(text: field, destinationCanTakeText: destinationCanTakeText, trusted: trusted)
        switch event {
        case .textChanged:
            return edit(field, context: context)
        case .send:
            return send(field, context: context)
        case .approved:
            return approve(context: context)
        case .denied, .timedOut, .scriptTyped, .scriptFailed:
            return absorb(HubDecision.reply(state, event, context: context))
        }
    }

    /// Cancel is not an approval. The draft stays, and no line is released.
    public mutating func cancel(sessionID: String) -> Step {
        guard sessionID == boundSessionID, !sessionID.isEmpty else { return .hold(state) }
        return absorb(HubDecision.reply(state, .cancel))
    }

    /// Records that the script finished. This does not release another line.
    public mutating func finished(sessionID: String, typed: Bool) -> Step {
        guard sessionID == boundSessionID, !sessionID.isEmpty else { return .hold(state) }
        let event: HubReplyEvent = typed ? .scriptTyped : .scriptFailed
        return absorb(HubDecision.reply(state, event))
    }

    private mutating func edit(_ field: String, context: HubReplyContext) -> Step {
        switch state.status {
        case .idle:
            return absorb(HubDecision.reply(state, .textChanged, context: context))
        case .drafting:
            state.draft = field
            state.script = nil
            return .hold(state)
        case .awaitingDecision, .sending, .unsupported, .failed:
            return absorb(HubDecision.reply(state, .textChanged, context: context))
        }
    }

    private mutating func send(_ field: String, context: HubReplyContext) -> Step {
        if state.status == .awaitingDecision || state.status == .sending {
            return absorb(HubDecision.reply(state, .send, context: context))
        }
        let drafted = HubDecision.reply(HubReplyState(), .textChanged, context: context)
        guard drafted.script == nil, drafted.state.script == nil else { return failClosed(keeping: field) }
        guard let cleaned = HubDecision.cleanedLine(field) else {
            return absorb(HubDecision.reply(drafted.state, .send, context: context))
        }
        guard context.destinationCanTakeText else {
            return absorb(HubDecision.reply(drafted.state, .send, context: context))
        }
        // A line that cannot be embedded must not reach the approval, or approval would release it.
        guard HubReplyTyping.canType(cleaned) else { return failClosed(keeping: field) }
        return absorb(HubDecision.reply(drafted.state, .send, context: context))
    }

    private mutating func approve(context: HubReplyContext) -> Step {
        guard state.status == .awaitingDecision else {
            return absorb(HubDecision.reply(state, .approved, context: context))
        }
        guard let preview = HubDecision.cleanedLine(state.draft) else {
            return absorb(HubDecision.reply(state, .approved, context: context))
        }
        guard context.destinationCanTakeText, HubReplyTyping.canType(preview) else {
            return absorb(HubDecision.reply(state, .denied, context: context))
        }
        return absorb(HubDecision.reply(state, .approved, context: context), allowLine: preview)
    }

    private mutating func failClosed(keeping field: String) -> Step {
        state = HubReplyState(status: .idle, draft: field, receipt: .notSent, script: nil)
        return .hold(state)
    }

    /// A line leaves only when this step released it and it is the line approval allowed.
    /// A script that was already on the state, and was not released again, stays where the machine left it.
    private mutating func absorb(_ outcome: HubReplyOutcome, allowLine: String? = nil) -> Step {
        if let released = outcome.script {
            let session = boundSessionID ?? ""
            if let allowLine, released == allowLine, outcome.state.script == allowLine,
               HubReplyTyping.canType(allowLine), !session.isEmpty, outcome.state.status == .sending {
                state = outcome.state
                return .typeLine(sessionID: session, line: allowLine, state: state)
            }
            var next = outcome.state
            next.script = nil
            if next.status == .sending {
                next = HubDecision.reply(next, .scriptFailed).state
                next.script = nil
            }
            state = next
            return .hold(state)
        }
        state = outcome.state
        if outcome.asksApproval, state.status == .awaitingDecision, state.script == nil {
            return .askInline(state)
        }
        return .hold(state)
    }
}

/// Which cleaned lines can be placed inside a quoted script without changing the script.
public enum HubReplyTyping {
    public static let maxLength = 2_000

    public static func canType(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= maxLength else { return false }
        return line.unicodeScalars.allSatisfy { !isBreak($0) }
    }

    /// Escapes a line for a double-quoted script string. Nil when the line must not be embedded.
    public static func escape(_ line: String) -> String? {
        guard canType(line) else { return nil }
        let escaped = line
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Quotes remain, each preceded by a backslash. A raw quote makes unescape fail.
        guard escaped.unicodeScalars.allSatisfy({ !isBreak($0) }) else { return nil }
        guard unescape(escaped) == line else { return nil }
        return escaped
    }

    public static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x20 || scalar.value == 0x7F { return true }
        if (0x80...0x9F).contains(scalar.value) { return true }
        if CharacterSet.newlines.contains(scalar) { return true }
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069, 0xFEFF:
            return true
        default:
            return scalar.properties.generalCategory == .control
        }
    }

    static func unescape(_ escaped: String) -> String? {
        var output = ""
        var pendingSlash = false
        for character in escaped {
            if pendingSlash {
                if character == "\\" || character == "\"" {
                    output.append(character)
                    pendingSlash = false
                } else {
                    return nil
                }
            } else if character == "\\" {
                pendingSlash = true
            } else if character == "\"" {
                return nil
            } else {
                output.append(character)
            }
        }
        return pendingSlash ? nil : output
    }
}

/// The last check before a script is executed. `approved` false never passes, including a well-formed script.
public enum HubReplyScriptGuard {
    public static func mayRun(script: String, line: String, approved: Bool) -> Bool {
        guard approved, let escaped = HubReplyTyping.escape(line) else { return false }
        guard script.unicodeScalars.allSatisfy({ !isStructuralBreak($0) }) else { return false }
        // Match the typed-text call, not every quoted word. A reply can repeat a word the
        // surrounding script already quotes. Exactly one call, and nothing else may type.
        let wrappers = [
            "do script \"\(escaped)\"",
            "write text \"\(escaped)\"",
        ]
        var hits = 0
        var remainder = script
        for wrapper in wrappers {
            let parts = remainder.components(separatedBy: wrapper)
            hits += parts.count - 1
            remainder = parts.joined()
        }
        guard hits == 1 else { return false }
        let blocked = ["do shell script", "shell script", "keystroke", "key code", "key down", "key up", "System Events"]
        for phrase in blocked where remainder.contains(phrase) {
            return false
        }
        return true
    }

    private static func isStructuralBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x2028 || scalar.value == 0x2029 || scalar.value == 0x0085
            || (0x80...0x9F).contains(scalar.value)
    }
}
