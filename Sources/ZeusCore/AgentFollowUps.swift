import Darwin
import Foundation

// MARK: Exact terminal tab

/// The terminal device an agent runs on, found from its process ancestry (the hook itself
/// has pipes, not a terminal, but Claude Code / Codex above it do).
public enum ControllingTTY {
    public static func find(startingAt pid: pid_t = getppid(), maxDepth: Int = 6) -> String? {
        var current = pid
        for _ in 0..<maxDepth {
            guard current > 1, let info = processInfo(current) else { return nil }
            let device = info.kp_eproc.e_tdev
            if device != -1, device != 0, let name = devname(device, S_IFCHR) {
                return "/dev/" + String(cString: name)
            }
            current = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}

/// AppleScript that selects the exact tab of an agent session in Terminal or iTerm2.
public enum TerminalTabScript {
    public static func script(for info: TerminalInfo) -> String? {
        switch info.targetBundleID {
        case "com.apple.Terminal":
            guard let tty = info.tty.flatMap(safe) else { return nil }
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            // ITERM_SESSION_ID is "w0t1p0:UUID"; the UUID is the session's unique id.
            let uuid = info.sessionID.flatMap { $0.split(separator: ":").last.map(String.init) }.flatMap(safe)
            let tty = info.tty.flatMap(safe)
            guard uuid != nil || tty != nil else { return nil }
            let test = [uuid.map { "unique id of s is \"\($0)\"" }, tty.map { "tty of s is \"\($0)\"" }]
                .compactMap { $0 }.joined(separator: " or ")
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if \(test) then
                                select w
                                select t
                                select s
                                activate
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

    /// Only plain tty paths and ids reach the script; anything else is dropped, never escaped.
    static func safe(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/-_.")
        guard !value.isEmpty, value.count < 120, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
}

// MARK: Robust question answers

/// How answers to Claude Code's AskUserQuestion travel back. `allowWithAnswers` lets the
/// tool run with the answers filled in; `denyWithAnswer` refuses the tool and puts the
/// answers in the refusal message, which every Claude Code version reads.
public enum QuestionAnswerPath: String, Codable, Sendable {
    case allowWithAnswers, denyWithAnswer

    public func decision(id: String, input: JSONValue?, answers: [String: [String]]) -> HookDecision {
        switch self {
        case .allowWithAnswers:
            return HookDecision(id: id, decision: .allow, updatedInput: AgentQuestion.answeredInput(input, answers: answers))
        case .denyWithAnswer:
            return HookDecision(id: id, decision: .deny, reason: Self.message(answers))
        }
    }

    public static func message(_ answers: [String: [String]]) -> String {
        let lines = answers.keys.sorted().compactMap { question -> String? in
            guard let labels = answers[question], !labels.isEmpty else { return nil }
            return "- \(question) → \(labels.joined(separator: ", "))"
        }
        return "The user already answered these questions in ZEUS:\n" + lines.joined(separator: "\n")
            + "\nContinue with these answers and do not ask them again."
    }
}

/// Learns whether this Claude Code honours answers sent with "allow". After an answer goes
/// out, the tool's result should contain it; if the result lacks it, or Claude Code says it
/// is waiting for input right after, the allow path is marked unsupported and later answers
/// use the deny-with-answer path.
public struct QuestionAnswerTracker: Codable, Equatable, Sendable {
    public struct Pending: Codable, Equatable, Sendable {
        public var session: String
        public var labels: [String]
        public var sentAt: Date
    }

    public private(set) var path: QuestionAnswerPath = .allowWithAnswers
    public private(set) var pending: Pending?
    /// How long after sending a "waiting for input" notification counts as "not honoured".
    public var window: TimeInterval = 15

    public init(path: QuestionAnswerPath = .allowWithAnswers) {
        self.path = path
    }

    public mutating func sent(session: String, answers: [String: [String]], at date: Date = Date()) {
        guard path == .allowWithAnswers else { pending = nil; return }
        pending = Pending(session: session, labels: answers.values.flatMap { $0 }, sentAt: date)
    }

    /// The tool's result for AskUserQuestion arrived (PostToolUse). Returns the verdict.
    @discardableResult
    public mutating func toolResult(session: String, text: String?) -> Bool? {
        guard let pending, pending.session == session else { return nil }
        self.pending = nil
        let honoured = pending.labels.allSatisfy { label in text?.localizedCaseInsensitiveContains(label) == true }
        if !honoured { path = .denyWithAnswer }
        return honoured
    }

    /// Claude Code notified that it is waiting for input.
    @discardableResult
    public mutating func waitingForInput(session: String, at date: Date = Date()) -> Bool {
        guard let pending, pending.session == session, date.timeIntervalSince(pending.sentAt) <= window else { return false }
        self.pending = nil
        path = .denyWithAnswer
        return true
    }

    /// Lets people try the allow path again (Settings), e.g. after updating Claude Code.
    public mutating func reset() {
        path = .allowWithAnswers
        pending = nil
    }
}
