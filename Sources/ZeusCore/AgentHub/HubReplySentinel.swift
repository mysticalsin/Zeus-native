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
        case 0x034F, 0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0:
            return true
        default:
            return false
        }
    }
}

/// The process in the target tab, read with the terminal's own AppleScript. A shell prompt is not an agent.
///
/// A bare process name is not enough to type. `HubReplyJobGuard` requires the tty foreground process
/// group and the foreground pid's executable, resolved with `proc_pidpath` (or `/proc/<pid>/exe`) and
/// checked against the allowlist. `verdict(name:)` still classifies a name. When `executablePath` is
/// set, or `name` itself contains a slash, `realpath` must land on `allowedPaths`. A shell stays
/// `.bareShell` even when a path is allowlisted.
public enum HubReplyForeground {
    public enum Verdict: Equatable, Sendable {
        case agent
        case bareShell
        case unknown
    }

    private static let shells: Set<String> = ["bash", "zsh", "sh", "fish", "dash", "ksh", "tcsh", "csh"]

    static func isShell(_ name: String) -> Bool {
        shells.contains(name)
    }

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

    /// A read that does not type and does not start a shell.
    /// Terminal's foreground process group is `HubReplyTTYReader`, not this script.
    /// iTerm2 may still read `jobName`. An unsafe tty produces an empty script.
    public static func queryScript(bundleID: String, tty: String) -> String {
        guard let tty = TerminalTabScript.safe(tty) else { return "" }
        switch bundleID {
        case "com.apple.Terminal":
            _ = tty
            return ""
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

/// One process on the reply tty. `stopped` is a Ctrl-Z job. `executablePath` is the binary, when the probe could see it.
public struct HubReplyProcessFact: Equatable, Sendable {
    public var pid: Int32
    public var pgid: Int32
    public var name: String
    public var executablePath: String?
    public var stopped: Bool

    public init(pid: Int32, pgid: Int32, name: String, executablePath: String? = nil, stopped: Bool = false) {
        self.pid = pid
        self.pgid = pgid
        self.name = name
        self.executablePath = executablePath
        self.stopped = stopped
    }
}

/// The tty at one moment. `foregroundPgid` is the process group that owns the terminal, or nil when that read failed.
public struct HubReplyTTYSnapshot: Equatable, Sendable {
    public var frontmostApp: String?
    public var foregroundPgid: Int32?
    public var processes: [HubReplyProcessFact]

    public init(frontmostApp: String?, foregroundPgid: Int32?, processes: [HubReplyProcessFact]) {
        self.frontmostApp = frontmostApp
        self.foregroundPgid = foregroundPgid
        self.processes = processes
    }
}

/// Whether the tty's foreground process group is the expected CLI.
/// The last name in a process list is not used. A stopped job, a background job, an empty CLI
/// list, an unknown process group, and a binary that is not on the allowlist are refused.
public enum HubReplyJobGuard {
    public static func mayType(
        snapshot: HubReplyTTYSnapshot,
        expectedApp: String,
        expectedCLI: Set<String>,
        allowedPaths: Set<String>
    ) -> Bool {
        guard !expectedCLI.isEmpty else { return false }
        if let front = snapshot.frontmostApp, front != expectedApp { return false }
        guard let pgid = snapshot.foregroundPgid else { return false }
        let foreground = snapshot.processes.filter { $0.pgid == pgid && !$0.stopped }
        guard !foreground.isEmpty else { return false }
        let shellInGroup = foreground.contains { process in
            HubReplyForeground.isShell(HubReplyForeground.normalizedToken(process.name) ?? "")
        }
        guard !shellInGroup else { return false }
        guard let leader = foreground.first(where: { $0.pid == pgid }) else { return false }
        guard let name = HubReplyForeground.normalizedToken(leader.name), expectedCLI.contains(name) else { return false }
        guard let path = leader.executablePath, !path.isEmpty else { return false }
        return HubReplyForeground.verdict(
            name: name, expected: expectedCLI, executablePath: path, allowedPaths: allowedPaths) == .agent
    }

    /// Return is safe when typing was allowed and the app is the target afterwards.
    /// The pre-typing snapshot may have no frontmost app: the typing script activates the terminal.
    /// A later snapshot whose front app is missing or different withholds Return. The process group must be unchanged.
    public static func maySubmit(
        before: HubReplyTTYSnapshot,
        after: HubReplyTTYSnapshot,
        expectedApp: String,
        expectedCLI: Set<String>,
        allowedPaths: Set<String>
    ) -> Bool {
        guard after.frontmostApp == expectedApp else { return false }
        guard let beforeGroup = before.foregroundPgid, beforeGroup == after.foregroundPgid else { return false }
        return mayType(snapshot: before, expectedApp: expectedApp, expectedCLI: expectedCLI, allowedPaths: allowedPaths)
            && mayType(snapshot: after, expectedApp: expectedApp, expectedCLI: expectedCLI, allowedPaths: allowedPaths)
    }

    /// `.agent` when the foreground group is the allowlisted CLI. `.bareShell` when that group is a shell.
    /// Anything else, including an unknown group, is `.unknown`.
    public static func verdict(
        snapshot: HubReplyTTYSnapshot,
        expectedApp: String,
        expectedCLI: Set<String>,
        allowedPaths: Set<String>
    ) -> HubReplyForeground.Verdict {
        if mayType(snapshot: snapshot, expectedApp: expectedApp, expectedCLI: expectedCLI, allowedPaths: allowedPaths) {
            return .agent
        }
        guard let pgid = snapshot.foregroundPgid else { return .unknown }
        let foreground = snapshot.processes.filter { $0.pgid == pgid && !$0.stopped }
        let shell = foreground.contains { process in
            HubReplyForeground.isShell(HubReplyForeground.normalizedToken(process.name) ?? "")
        }
        return shell ? .bareShell : .unknown
    }
}

/// Reads the tty foreground process group with `/bin/ps` and a fixed argument vector. No shell is started.
public enum HubReplyTTYReader {
    public static let executable = "/bin/ps"

    /// Nil when `tty` is not a plain device path, so the argument vector is never built for it.
    public static func arguments(forTTY tty: String) -> [String]? {
        guard let tty = TerminalTabScript.safe(tty), tty.hasPrefix("/dev/") else { return nil }
        return ["-o", "pid=,pgid=,tpgid=,stat=,comm=", "-t", tty]
    }

    /// `ps` rows into a snapshot. `pathForPID` is `proc_pidpath` on macOS and `/proc/<pid>/exe` elsewhere.
    /// Rows that disagree about the tty's foreground process group produce an unknown group.
    public static func snapshot(
        frontmostApp: String?,
        ps output: String,
        pathForPID: (Int32) -> String? = { _ in nil }
    ) -> HubReplyTTYSnapshot {
        var processes: [HubReplyProcessFact] = []
        var group: Int32?
        var disagreed = false
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 5,
                  let pid = Int32(fields[0]),
                  let pgid = Int32(fields[1]),
                  let tpgid = Int32(fields[2]),
                  tpgid > 0 else { continue }
            if let seen = group, seen != tpgid { disagreed = true }
            group = tpgid
            let stat = fields[3]
            let name = fields.dropFirst(4).joined(separator: " ")
            processes.append(HubReplyProcessFact(
                pid: pid,
                pgid: pgid,
                name: name,
                executablePath: pathForPID(pid),
                stopped: stat.contains("T")))
        }
        return HubReplyTTYSnapshot(
            frontmostApp: frontmostApp,
            foregroundPgid: disagreed ? nil : group,
            processes: processes)
    }

    /// The live read. `frontmostApp` is supplied by the caller. An unsafe tty is an unknown group.
    public static func read(tty: String, frontmostApp: String?) -> HubReplyTTYSnapshot {
        guard let arguments = arguments(forTTY: tty), let output = run(arguments) else {
            return HubReplyTTYSnapshot(frontmostApp: frontmostApp, foregroundPgid: nil, processes: [])
        }
        return snapshot(frontmostApp: frontmostApp, ps: output, pathForPID: executablePath(pid:))
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    /// `proc_pidpath` on macOS. On Linux, the `/proc/<pid>/exe` link.
    public static func executablePath(pid: Int32) -> String? {
        #if os(macOS)
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let length = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return proc_pidpath(pid, base, UInt32(raw.count))
        }
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
        #else
        return HubReplyForeground.resolve("/proc/\(pid)/exe")
        #endif
    }
}

#if os(macOS)
@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ buffersize: UInt32) -> Int32
#endif
