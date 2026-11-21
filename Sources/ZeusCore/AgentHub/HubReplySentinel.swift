import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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

/// Hidden and bidirectional scalars. They are refused and left in the draft. They are not stripped.
/// Every Unicode `Cf` (format) scalar is refused. So are U+FEFF, U+00AD, U+180E, U+2061...U+2064,
/// the tag block U+E0000...U+E007F, variation selectors U+FE00...U+FE0F and U+E0100...U+E01EF,
/// and the bidi controls, including when a Unicode version files one of them outside `Cf`.
public enum HubReplyHidden {
    public static func containsMark(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isMark)
    }

    public static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .format { return true }
        switch scalar.value {
        case 0x00AD, 0x061C, 0x180E, 0x200E, 0x200F, 0xFEFF:
            return true
        case 0x202A...0x202E, 0x2061...0x2064, 0x2066...0x2069:
            return true
        case 0xFE00...0xFE0F, 0xE0000...0xE007F, 0xE0100...0xE01EF:
            return true
        default:
            return false
        }
    }
}

/// The process in the target tab, read with the terminal's own AppleScript. A shell prompt is not an agent.
///
/// Terminal's `processes` and iTerm's `jobName` are process names, not executable paths. A bare name is
/// matched against `expected` and the shell set. That is the limit of those dictionaries: a renamed
/// binary can still match a name, and this type cannot see the inode behind it.
/// When `executablePath` is set, or `name` itself contains a slash, the path is resolved with `realpath`
/// and must be one of `allowedPaths` after the same resolution. A path that does not resolve, or is not
/// on that allowlist, is `.unknown`. A shell stays `.bareShell` even when a path is allowlisted.
public enum HubReplyForeground {
    public enum Verdict: Equatable, Sendable {
        case agent
        case bareShell
        case unknown
    }

    private static let shells: Set<String> = ["bash", "zsh", "sh", "fish", "dash", "ksh", "tcsh", "csh"]

    /// `name` is the foreground process, or nil when the query could not see one.
    /// A shell is refused. Any other process that is not the expected CLI is unknown, and also refused.
    /// A path is accepted only when its resolved real path is on `allowedPaths` and its final component is expected.
    public static func verdict(
        name: String?,
        expected: Set<String>,
        executablePath: String? = nil,
        allowedPaths: Set<String> = []
    ) -> Verdict {
        if let token = normalizedToken(name), shells.contains(token) { return .bareShell }
        let pathCandidate = executablePath ?? name.flatMap { $0.contains("/") ? $0 : nil }
        if let pathCandidate {
            if let token = normalizedToken(pathCandidate), shells.contains(token) { return .bareShell }
            guard let resolved = resolve(pathCandidate), let base = normalizedToken(resolved), expected.contains(base) else {
                return .unknown
            }
            if let token = normalizedToken(name), name?.contains("/") != true, token != base { return .unknown }
            let allowed = Set(allowedPaths.compactMap(resolve))
            return allowed.contains(resolved) ? .agent : .unknown
        }
        guard let token = normalizedToken(name), expected.contains(token) else { return .unknown }
        return .agent
    }

    /// The last path component, without one leading dash, lowercased. Nil when nothing is left.
    static func normalizedToken(_ name: String?) -> String? {
        guard var token = name?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        if token.hasPrefix("-") { token.removeFirst() }
        if let slash = token.lastIndex(of: "/") { token = String(token[token.index(after: slash)...]) }
        token = token.lowercased()
        return token.isEmpty ? nil : token
    }

    /// `realpath(3)`. Nil when the path does not exist.
    public static func resolve(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil, let end = buffer.firstIndex(of: 0) else { return nil }
        let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
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
                            -- `processes` is an unordered list. It does not mark the foreground process,
                            -- so the last item is not that process. Fail closed.
                            set names to processes of t
                            return ""
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
