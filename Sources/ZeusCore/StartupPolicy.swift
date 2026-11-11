import Foundation

/// A launch-time service or entry point that an explicit QA startup (`--qa-startup <root>`) may deny.
public enum StartupService: String, CaseIterable, Sendable {
    // The only service a QA startup keeps: the bare status item (it opens nothing).
    case statusItem
    // Everything else is denied in QA, including the permission status read, the notch and the menu bar
    // panel (non-interactive startup).
    case permissionStatusRead, notchUI, panelUI, intelligence, windowSharing, systemNotifications
    case buddy, topBarServices, beamer, dictation, teleprompter, prompterWatcher
    case insomniaLaunch, insomniaShutdown, chatBrain, chatHotkey
    case usage, proactive, stickiesRestore, routines, helperRefresh, voiceTurn
    case appIndex, projectScanner, macControl, avatarFeed, shortcuts, todo
    case sleepWatch, notificationPeeker, settingsCatalog, updates, agentServer
    case cliInstall, assistantKeyImport, talkHotkey, polyglotHotkey, wakeWord, pointingHotkey
    case connectionsRefresh, autoOnboarding, demoArg, motionOpenArg, deepLinks
    case settingsWindow, onboardingWindow, chatWindow, demoPlayback
}

public enum StartupMode: Equatable, Sendable {
    case normal
    case qa(root: String)
    case invalid(reason: String)
}

/// Decides, from argv and the launch environment alone, whether this process is a contained QA
/// startup. Pure: no filesystem, no environment writes, no exit. Without `--qa-startup` the answer is
/// always `.normal` and the environment is not looked at.
public struct StartupPolicy: Equatable, Sendable {
    public static let flag = "--qa-startup"
    public static let markerFileName = ".zeus-qa-root"
    public static let rootPrefix = "zeus-qa-"
    public static let socketLimit = 103

    public let mode: StartupMode

    public init(mode: StartupMode) { self.mode = mode }

    public static let normal = StartupPolicy(mode: .normal)

    /// The process-wide policy: `.normal` until main.swift sets it once, before anything else starts.
    nonisolated(unsafe) public static var current: StartupPolicy = .normal

    public var isQA: Bool {
        if case .qa = mode { return true }
        return false
    }

    public static let qaAllowed: Set<StartupService> = [.statusItem]

    /// The line a QA startup prints at the probe boundary. It is not proof of OS isolation: it only says the
    /// boundary was reached with no Zeus code having read preferences.
    public static let probeBoundaryLine = "qa-startup probe boundary reached (not OS isolation)"
    public static let probeExitCode: Int32 = 0

    /// Full GUI QA needs an OS, account or CFPreferences isolation that does not exist yet. An unresolved
    /// runtime dependency, not a switch to turn on.
    public static let fullGUIQASupported = false

    public func allows(_ service: StartupService) -> Bool {
        switch mode {
        case .normal: return true
        case .qa: return Self.qaAllowed.contains(service)
        case .invalid: return false
        }
    }

    /// Flags (and `debug` as argv[1]) that start some other mode and so never combine with QA.
    public static let conflictingFlags: Set<String> = [
        "debug", "--jev-settings-test", "--snapshots", "--keychain-import", "--keychain-selftest",
        "--ask", "--install-hooks", "--uninstall-hooks", "--browseruse-smoke", "--demo", "--motion-open",
        "--settings-only", "--onboarding-only", "--voice-selftest", "--engine-logos", "--render-film",
        "--onboarding-step", "--onboarding-agent", "--onboarding-fresh", "--settings-section", "--tts-sample",
        "--jev-smoke", "--require-keys", "--drive-dryrun", "--drive-snapshot", "--screen-awareness-dryrun",
        "--annotate-dryrun", "--agent-dryrun", "--codex-replay", "--microphones", "--transcribe", "--chrome",
        "--snapshot-scales", "--snapshot-match", "--pointing-selftest",
    ]

    /// Variables that must be absent in QA: they point Zeus at a brain fixture or the login keychain.
    public static let forbiddenEnvironment: [String] = ["ZEUS_BRAIN_FIXTURE", "ZEUS_LOGIN_KEYCHAIN"]

    /// What the launcher must have set for `root`. main.swift only checks these; it never sets them.
    public static func requiredEnvironment(root: String) -> [String: String] {
        [
            "HOME": root + "/home",
            "CFFIXED_USER_HOME": root + "/home",
            "ZEUS_SUPPORT_DIR": root + "/support",
            "ZEUS_SOCKET": root + "/support/zeus.sock",
            "ZEUS_LOG_DIR": root + "/logs",
            "ZEUS_AGENT_CONFIG_HOME": root + "/agents",
            "ZEUS_CLAUDE_SETTINGS": root + "/claude-settings.json",
            "CLAUDE_CONFIG_DIR": root + "/claude",
            "CODEX_HOME": root + "/codex",
            "TMPDIR": root + "/tmp/",
        ]
    }

    /// What `lstat` reported for the QA root and its marker file.
    public struct RootObservation: Equatable, Sendable {
        public let isDirectory: Bool
        public let ownerMatches: Bool
        public let markerIsRegularFile: Bool

        public init(isDirectory: Bool, ownerMatches: Bool, markerIsRegularFile: Bool) {
            self.isDirectory = isDirectory
            self.ownerMatches = ownerMatches
            self.markerIsRegularFile = markerIsRegularFile
        }
    }

    /// nil when the root is a real directory owned by this user holding the marker file; otherwise the refusal reason.
    public static func verifyRoot(_ observed: RootObservation) -> String? {
        guard observed.isDirectory else { return "root is not a real directory" }
        guard observed.ownerMatches else { return "root is not owned by this user" }
        guard observed.markerIsRegularFile else { return "root has no \(markerFileName) marker" }
        return nil
    }

    /// The only bundle identifier the launcher accepts for an inspected artifact.
    public static let requiredBundleIdentifier = "app.zeus.mac"

    /// True for exactly 64 lowercase hex digits.
    public static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// Manifest format `zeus-manifest-v1`, mirrored by scripts/qa-startup-launch.sh: a compact JSON object of
    /// bundle-relative path to lowercase SHA-256 hex, keys sorted by byte order, no whitespace, no trailing
    /// newline. Its SHA-256 is the manifest digest. nil when a path is not JSON-safe or a hash is malformed.
    public static let manifestFormatVersion = "zeus-manifest-v1"

    public static func manifestJSON(_ entries: [String: String]) -> String? {
        var parts: [String] = []
        for path in entries.keys.sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }) {
            guard let hash = entries[path], isSHA256Hex(hash), !path.isEmpty, !path.hasPrefix("/"),
                  path.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7f && $0 != 0x22 && $0 != 0x5c }) else { return nil }
            parts.append("\"\(path)\":\"\(hash)\"")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// The home, support and temporary directories as the running process sees them.
    public struct PathObservation: Equatable, Sendable {
        public let nsHome: String
        public let userHome: String
        public let tildeHome: String
        public let supportDirectory: String
        public let temporaryDirectory: String

        public init(nsHome: String, userHome: String, tildeHome: String, supportDirectory: String, temporaryDirectory: String) {
            self.nsHome = nsHome
            self.userHome = userHome
            self.tildeHome = tildeHome
            self.supportDirectory = supportDirectory
            self.temporaryDirectory = temporaryDirectory
        }
    }

    /// nil when every home, support and temporary lookup stays inside `root`; otherwise the refusal reason.
    public static func verifyPaths(_ observed: PathObservation, root: String) -> String? {
        let home = root + "/home"
        guard observed.nsHome == home else { return "home directory is not \(home)" }
        guard observed.userHome == home else { return "user home directory is not \(home)" }
        guard observed.tildeHome == home else { return "tilde home is not \(home)" }
        guard observed.supportDirectory == root + "/support" else { return "support directory is not \(root)/support" }
        let temp = root + "/tmp"
        guard observed.temporaryDirectory == temp || observed.temporaryDirectory.hasPrefix(temp + "/") else {
            return "temporary directory is not under \(temp)/"
        }
        return nil
    }

    /// - Parameters:
    ///   - arguments: the full argv, program name first.
    ///   - environment: the process environment as launched.
    ///   - launchTemporaryDirectory: the per-user temporary directory from before the launcher's
    ///     override (not `TMPDIR`), e.g. `/private/var/folders/.../T/`.
    ///   - realHome: the account's real home directory (not `HOME`).
    public static func decide(arguments: [String], environment: [String: String],
                              launchTemporaryDirectory: String, realHome: String) -> StartupPolicy {
        let rest = Array(arguments.dropFirst())
        if !rest.contains(where: { $0 == flag || $0.hasPrefix(flag + "=") }) { return .normal }

        func invalid(_ reason: String) -> StartupPolicy { StartupPolicy(mode: .invalid(reason: reason)) }

        let positions = rest.indices.filter { rest[$0] == flag }
        if rest.contains(where: { $0.hasPrefix(flag + "=") }) { return invalid("\(flag) takes its value as the next argument") }
        guard positions.count == 1 else { return invalid("\(flag) given more than once") }
        let valueIndex = positions[0] + 1
        guard valueIndex < rest.count else { return invalid("\(flag) has no value") }
        let root = rest[valueIndex]
        if root.hasPrefix("--") { return invalid("\(flag) value looks like a flag") }

        if rest.first == "debug" { return invalid("\(flag) cannot combine with debug") }
        if let clash = rest.first(where: { $0 != "debug" && conflictingFlags.contains($0) }) {
            return invalid("\(flag) cannot combine with \(clash)")
        }

        // Exactly `--qa-startup <root>`: any other argument could be a `-key value` pair that UserDefaults
        // turns into an argument-domain override of a saved value.
        guard rest == [flag, root] else { return invalid("\(flag) takes no other arguments") }

        guard root.hasPrefix("/") else { return invalid("root is not absolute") }
        guard root != "/", !root.hasSuffix("/") else { return invalid("root is not in standard form") }
        let components = root.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return invalid("root is not in standard form") }
        guard let last = components.last, last.hasPrefix(rootPrefix) else { return invalid("root name must start with \(rootPrefix)") }

        var tempRoots = ["/private/tmp/", "/tmp/"]
        if launchTemporaryDirectory.hasPrefix("/"), launchTemporaryDirectory != "/" {
            tempRoots.append(launchTemporaryDirectory.hasSuffix("/") ? launchTemporaryDirectory : launchTemporaryDirectory + "/")
        }
        guard tempRoots.contains(where: { root.hasPrefix($0) }) else { return invalid("root is not under a temporary directory") }

        if !realHome.isEmpty {
            let library = realHome.hasSuffix("/") ? realHome + "Library" : realHome + "/Library"
            if root == library || root.hasPrefix(library + "/") { return invalid("root is inside the real Library") }
        }

        if (root + "/support/zeus.sock").utf8.count > socketLimit { return invalid("socket path is too long") }

        for (key, value) in requiredEnvironment(root: root) where environment[key] != value {
            return invalid("environment \(key) is missing or not \(value)")
        }
        for key in forbiddenEnvironment where environment[key] != nil {
            return invalid("environment \(key) must not be set")
        }
        return StartupPolicy(mode: .qa(root: root))
    }
}
