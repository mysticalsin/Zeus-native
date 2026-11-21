import Foundation

/// The terminal tab a pending reply names. `expectedCLI` is the agent process, not part of the tab identity.
public struct HubReplyTarget: Equatable, Sendable {
    public var app: String
    public var tty: String
    public var expectedCLI: Set<String>

    public init(app: String, tty: String, expectedCLI: Set<String>) {
        self.app = app
        self.tty = tty
        self.expectedCLI = expectedCLI
    }

    /// The app a person reads, and the tty the tab is resolved by. Nil when either is missing.
    public static func make(info: TerminalInfo?, agent: String) -> HubReplyTarget? {
        guard let info, let tty = info.tty, !tty.isEmpty, let bundle = info.targetBundleID else { return nil }
        let app: String
        switch bundle {
        case "com.apple.Terminal": app = "Terminal"
        case "com.googlecode.iterm2": app = "iTerm2"
        default: app = bundle
        }
        return HubReplyTarget(app: app, tty: tty, expectedCLI: HubReplyForeground.expectedCLI(agent: agent))
    }
}

/// What the pending reply says, and whether Approve is still looking at that same tab.
public enum HubReplyTargetGate {
    public static func cardSentence(_ target: HubReplyTarget) -> String {
        "Type this into \(target.app) on \(target.tty)?"
    }

    /// App and tty only. A missing tab has vanished. A different app or tty has changed.
    public static func refusal(shown: HubReplyTarget, current: HubReplyTarget?) -> HubReplyReceipt? {
        guard let current else { return .tabVanished }
        if current.app != shown.app || current.tty != shown.tty { return .tabChanged }
        return nil
    }
}

/// Zero-width and bidirectional marks. They are refused and left in the draft. They are not stripped.
public enum HubReplyHidden {
    public static func containsMark(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isMark)
    }

    public static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B...0x200F, 0x2060, 0x061C, 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
        }
    }
}

/// The process in the target tab, read with the terminal's own AppleScript. A shell prompt is not an agent.
public enum HubReplyForeground {
    public enum Verdict: Equatable, Sendable {
        case agent
        case bareShell
        case unknown
    }

    private static let shells: Set<String> = ["bash", "zsh", "sh", "fish", "dash", "ksh", "tcsh", "csh"]

    /// `name` is the foreground process, or nil when the query could not see one.
    /// A shell is refused. Any other process that is not the expected CLI is unknown, and also refused.
    public static func verdict(name: String?, expected: Set<String>) -> Verdict {
        guard var token = name?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return .unknown }
        if token.hasPrefix("-") { token.removeFirst() }
        if let slash = token.lastIndex(of: "/") { token = String(token[token.index(after: slash)...]) }
        token = token.lowercased()
        if shells.contains(token) { return .bareShell }
        if expected.contains(token) { return .agent }
        return .unknown
    }

    /// The CLI Zeus expects in that tab, from the session's agent name.
    public static func expectedCLI(agent: String) -> Set<String> {
        switch agent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude", "claude code", "claudecode": ["claude"]
        case "codex", "codex cli": ["codex"]
        case "gemini", "gemini cli": ["gemini"]
        case "cursor", "cursor agent", "cursor-agent": ["cursor-agent"]
        default: []
        }
    }

    /// A read of the foreground process. It does not type and it does not start a shell.
    /// Terminal uses the tab's `processes`. iTerm2 uses the session's `jobName`.
    /// Both are the apps' existing AppleScript dictionaries. An unsafe tty produces an empty script.
    public static func queryScript(bundleID: String, tty: String) -> String {
        guard let tty = TerminalTabScript.safe(tty) else { return "" }
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set names to processes of t
                            if (count of names) is 0 then return ""
                            return last item of names
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                return variable named "jobName" of s
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return ""
            """
        default:
            return ""
        }
    }
}
