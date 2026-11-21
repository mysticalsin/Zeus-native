import Foundation

/// Replying to a running agent from the notch. Claude Code and Codex hooks only report events and
/// answer permission requests; they have no way to push a new prompt into a live session. The one
/// path that exists is typing into the session's own terminal tab, which Terminal and iTerm2 allow
/// through AppleScript. Other terminals (Ghostty, Warp, editors) cannot be typed into this way.
public enum AgentReply {
    public static let maxLength = 2000

    /// One line, no control characters and no newlines. Nil when nothing is left to send.
    public static func sanitize(_ text: String) -> String? {
        let flat = text.unicodeScalars.map { scalar -> Character in
            isStripped(scalar) ? " " : Character(scalar)
        }
        let line = String(flat).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxLength))
    }

    /// C0 and C1 controls, DEL, and Unicode newlines. They are not typed.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x20 || scalar.value == 0x7F { return true }
        if (0x80...0x9F).contains(scalar.value) { return true }
        return CharacterSet.newlines.contains(scalar)
    }

    /// Whether ZEUS can type into this terminal.
    public static func supports(_ info: TerminalInfo?) -> Bool {
        guard let info else { return false }
        return script(for: info, text: "x") != nil
    }

    /// The AppleScript that types `text` and Return into the session's exact tab.
    /// Terminal receives literal keystrokes in the tab that is already open. The text is not a new shell command.
    public static func script(for info: TerminalInfo, text: String) -> String? {
        guard let line = sanitize(text) else { return nil }
        let escaped = appleScriptString(line)
        switch info.targetBundleID {
        case "com.apple.Terminal":
            guard let tty = info.tty.flatMap(TerminalTabScript.safe) else { return nil }
            let strokes = literalKeystrokes(line)
            guard !strokes.isEmpty else { return nil }
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            tell application "System Events" to tell process "Terminal"
                                \(strokes)
                                keystroke return
                            end tell
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            let uuid = info.sessionID.flatMap { $0.split(separator: ":").last.map(String.init) }.flatMap(TerminalTabScript.safe)
            let tty = info.tty.flatMap(TerminalTabScript.safe)
            guard uuid != nil || tty != nil else { return nil }
            let test = [uuid.map { "unique id of s is \"\($0)\"" }, tty.map { "tty of s is \"\($0)\"" }]
                .compactMap { $0 }.joined(separator: " or ")
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if \(test) then
                                tell s to write text "\(escaped)"
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    /// Escapes a line for a double-quoted AppleScript string.
    private static func appleScriptString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Literal keystrokes, each at most 20 UTF-16 units. Controls and newlines are already gone.
    private static func literalKeystrokes(_ line: String) -> String {
        KeystrokeTyping.pieces(line, limit: 20).compactMap { piece -> String? in
            guard case .text(let chunk) = piece, !chunk.isEmpty else { return nil }
            return "keystroke \"\(appleScriptString(chunk))\""
        }.joined(separator: "\n")
    }
}

public enum AgentReplyOutcome: Equatable, Sendable {
    case sent
    /// Nothing to send (empty after cleaning).
    case empty
    /// The person said no on the approval card.
    case declined
    /// The terminal is unknown or cannot be typed into: open it and reply there.
    case unsupported
    /// The script ran but found no matching tab, or failed.
    case failed
}

/// The reply path with its three outside steps injected, so tests use a fake terminal:
/// find the session's terminal, ask for approval, run the script.
public struct AgentReplySender: Sendable {
    public var terminal: @Sendable (String) -> TerminalInfo?
    public var approve: @Sendable (_ agent: String, _ text: String) async -> Bool
    public var run: @Sendable (_ script: String) async -> Bool

    public init(terminal: @escaping @Sendable (String) -> TerminalInfo?,
                approve: @escaping @Sendable (String, String) async -> Bool,
                run: @escaping @Sendable (String) async -> Bool) {
        self.terminal = terminal; self.approve = approve; self.run = run
    }

    /// Runs on the main actor: the terminal lookup reads main-actor state, and off it would trap.
    @MainActor
    public func send(_ text: String, to session: String, agent: String) async -> AgentReplyOutcome {
        guard let line = AgentReply.sanitize(text) else { return .empty }
        guard let info = terminal(session), let script = AgentReply.script(for: info, text: line) else { return .unsupported }
        guard await approve(agent, line) else { return .declined }
        return await run(script) ? .sent : .failed
    }
}
