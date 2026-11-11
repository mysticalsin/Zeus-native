import Foundation
import Testing
import ZeusCore

@Suite("QA startup containment policy")
struct StartupPolicyTests {
    static let root = "/private/tmp/zeus-qa-abc123"
    static let realHome = "/Users/someone"
    static let userTemp = "/private/var/folders/xx/yyyy/T/"

    /// Decides for `extra` arguments (default: QA on `Self.root`) with the exact required environment
    /// for `Self.root` unless `environment` is given.
    func decide(_ extra: [String]? = nil, environment: [String: String]? = nil,
                realHome: String = Self.realHome) -> StartupPolicy {
        StartupPolicy.decide(arguments: ["/Zeus.app/Contents/MacOS/Zeus"] + (extra ?? ["--qa-startup", Self.root]),
                             environment: environment ?? StartupPolicy.requiredEnvironment(root: Self.root),
                             launchTemporaryDirectory: Self.userTemp, realHome: realHome)
    }

    /// QA on `root` with the exact required environment for that same `root`.
    func decide(root: String, realHome: String = Self.realHome) -> StartupPolicy {
        decide(["--qa-startup", root], environment: StartupPolicy.requiredEnvironment(root: root), realHome: realHome)
    }

    func assertInvalid(_ policy: StartupPolicy, reason expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .invalid(let reason) = policy.mode else {
            Issue.record("expected invalid, got \(policy.mode)", sourceLocation: sourceLocation)
            return
        }
        #expect(reason.contains(expected), "reason \"\(reason)\" does not contain \"\(expected)\"", sourceLocation: sourceLocation)
        for service in StartupService.allCases {
            #expect(!policy.allows(service), "\(service) allowed while invalid", sourceLocation: sourceLocation)
        }
    }

    @Test func validQARootDeniesEverySensitiveService() {
        let policy = decide()
        #expect(policy.mode == .qa(root: Self.root))
        #expect(policy.isQA)
        for service in StartupService.allCases {
            #expect(policy.allows(service) == StartupPolicy.qaAllowed.contains(service), "\(service)")
        }
        #expect(StartupPolicy.qaAllowed == [.statusItem])
    }

    @Test func qaDeniesPermissionStatusRead() {
        let policy = decide()
        #expect(policy.isQA)
        #expect(!policy.allows(.permissionStatusRead))
        #expect(!StartupPolicy.qaAllowed.contains(.permissionStatusRead))
        #expect(StartupPolicy.normal.allows(.permissionStatusRead))
    }

    @Test func rootUnderLaunchTemporaryDirectoryIsAccepted() {
        let root = "/private/var/folders/xx/yyyy/T/zeus-qa-1"
        #expect(decide(root: root).mode == .qa(root: root))
    }

    @Test func invalidRootsFailClosed() {
        let cases: [(root: String, reason: String)] = [
            ("relative/zeus-qa-1", "not absolute"),
            ("/private/tmp/../zeus-qa-1", "standard form"),
            ("/private/tmp/./zeus-qa-1", "standard form"),
            ("/private/tmp//zeus-qa-1", "standard form"),
            ("/private/tmp/zeus-qa-1/", "standard form"),
            ("/", "standard form"),
            ("/Users/someone/Library/zeus-qa-1", "temporary directory"),
            ("/Users/someone/Library/x/zeus-qa-1", "temporary directory"),
            ("/private/tmp/qa-1", "root name must start with"),
            ("/Users/someone/zeus-qa-1", "temporary directory"),
            ("/var/zeus-qa-1", "temporary directory"),
            ("/private/tmp/zeus-qa-" + String(repeating: "x", count: 100), "socket path is too long"),
        ]
        for item in cases {
            assertInvalid(decide(root: item.root), reason: item.reason)
        }
    }

    /// The Library rule is only reachable when the real home itself sits under an allowed temp root.
    @Test func rootInsideRealLibraryFailsClosed() {
        let home = "/private/tmp/zeus-fake-home"
        assertInvalid(decide(root: home + "/Library/zeus-qa-1", realHome: home), reason: "inside the real Library")
        assertInvalid(decide(root: home + "/Library/x/zeus-qa-1", realHome: home + "/"), reason: "inside the real Library")
        #expect(decide(root: home + "/zeus-qa-1", realHome: home).mode == .qa(root: home + "/zeus-qa-1"))
    }

    @Test func invalidArgumentsFailClosed() {
        assertInvalid(decide(["--qa-startup"]), reason: "has no value")
        assertInvalid(decide(["--qa-startup", "--demo"]), reason: "looks like a flag")
        assertInvalid(decide(["--qa-startup", Self.root, "--qa-startup", Self.root]), reason: "more than once")
        assertInvalid(decide(["--qa-startup=\(Self.root)"]), reason: "takes its value as the next argument")
        for flag in StartupPolicy.conflictingFlags where flag != "debug" {
            assertInvalid(decide(["--qa-startup", Self.root, flag]), reason: "cannot combine with \(flag)")
        }
        assertInvalid(decide(["debug", "--qa-startup", Self.root]), reason: "cannot combine with debug")
    }

    @Test func conflictingFlagsCoverEveryOtherModeFlag() {
        let required: [String] = [
            "--onboarding-step", "--onboarding-agent", "--onboarding-fresh", "--settings-section", "--tts-sample",
            "--jev-smoke", "--require-keys", "--drive-dryrun", "--drive-snapshot", "--screen-awareness-dryrun",
            "--annotate-dryrun", "--agent-dryrun", "--codex-replay", "--microphones", "--transcribe", "--chrome",
            "--snapshot-scales", "--snapshot-match",
        ]
        for flag in required {
            #expect(StartupPolicy.conflictingFlags.contains(flag), "\(flag)")
            assertInvalid(decide(["--qa-startup", Self.root, flag]), reason: "cannot combine with \(flag)")
            assertInvalid(decide([flag, "--qa-startup", Self.root]), reason: "cannot combine with \(flag)")
        }
    }

    @Test func environmentMismatchFailsClosed() {
        let required = StartupPolicy.requiredEnvironment(root: Self.root)
        for key in required.keys {
            var missing = required
            missing[key] = nil
            assertInvalid(decide(environment: missing), reason: "environment \(key)")
            var different = required
            different[key] = "/elsewhere"
            assertInvalid(decide(environment: different), reason: "environment \(key)")
        }
        for key in StartupPolicy.forbiddenEnvironment {
            assertInvalid(decide(environment: required.merging([key: "1"]) { $1 }), reason: "environment \(key) must not be set")
        }
    }

    @Test func normalAllowsEverythingAndIgnoresEnvironment() {
        let stray = ["ZEUS_BRAIN_FIXTURE": "1", "ZEUS_SUPPORT_DIR": "/x", "HOME": "/nope"]
        for arguments in [["Zeus"], ["Zeus", "--demo"], ["Zeus", "debug", "hud-state"], ["Zeus", "--jev-settings-test"]] {
            let policy = StartupPolicy.decide(arguments: arguments, environment: stray,
                                              launchTemporaryDirectory: "", realHome: "")
            #expect(policy == .normal)
            #expect(!policy.isQA)
            for service in StartupService.allCases { #expect(policy.allows(service)) }
        }
        #expect(StartupPolicy.current == .normal)
    }

    @Test func requiredEnvironmentIsExact() {
        let root = "/tmp/zeus-qa-9"
        #expect(StartupPolicy.requiredEnvironment(root: root) == [
            "HOME": "/tmp/zeus-qa-9/home",
            "CFFIXED_USER_HOME": "/tmp/zeus-qa-9/home",
            "ZEUS_SUPPORT_DIR": "/tmp/zeus-qa-9/support",
            "ZEUS_SOCKET": "/tmp/zeus-qa-9/support/zeus.sock",
            "ZEUS_LOG_DIR": "/tmp/zeus-qa-9/logs",
            "ZEUS_AGENT_CONFIG_HOME": "/tmp/zeus-qa-9/agents",
            "ZEUS_CLAUDE_SETTINGS": "/tmp/zeus-qa-9/claude-settings.json",
            "CLAUDE_CONFIG_DIR": "/tmp/zeus-qa-9/claude",
            "CODEX_HOME": "/tmp/zeus-qa-9/codex",
            "TMPDIR": "/tmp/zeus-qa-9/tmp/",
        ])
    }

    @Test func denylistInvariant() {
        let mustDeny: [StartupService] = [
            .wakeWord, .assistantKeyImport, .routines, .insomniaLaunch, .insomniaShutdown, .layaShutdown, .cliInstall,
            .agentServer, .updates, .connectionsRefresh, .settingsWindow, .chatBrain, .chatWindow, .deepLinks,
            .onboardingWindow, .demoPlayback, .voiceTurn, .talkHotkey, .pointingHotkey, .dictation, .teleprompter,
            .notchUI, .panelUI, .intelligence, .windowSharing, .systemNotifications,
        ]
        for service in mustDeny { #expect(!StartupPolicy.qaAllowed.contains(service), "\(service)") }
    }

    // MARK: paths, defaults canary, argv, launcher text (pure values; nothing live is read or run)

    static let digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    func observation(_ change: (inout [String: String]) -> Void = { _ in }) -> StartupPolicy.PathObservation {
        var values = [
            "nsHome": Self.root + "/home", "userHome": Self.root + "/home", "tildeHome": Self.root + "/home",
            "support": Self.root + "/support", "temp": Self.root + "/tmp/",
        ]
        change(&values)
        return StartupPolicy.PathObservation(nsHome: values["nsHome"]!, userHome: values["userHome"]!,
                                             tildeHome: values["tildeHome"]!, supportDirectory: values["support"]!,
                                             temporaryDirectory: values["temp"]!)
    }

    @Test func verifyPathsAcceptsAMatchingObservation() {
        #expect(StartupPolicy.verifyPaths(observation(), root: Self.root) == nil)
        #expect(StartupPolicy.verifyPaths(observation { $0["temp"] = Self.root + "/tmp" }, root: Self.root) == nil)
        #expect(StartupPolicy.verifyPaths(observation { $0["temp"] = Self.root + "/tmp/sub/" }, root: Self.root) == nil)
    }

    @Test func verifyPathsNamesEachWrongField() {
        let cases: [(key: String, value: String, reason: String)] = [
            ("nsHome", "/Users/someone", "home directory is not \(Self.root)/home"),
            ("userHome", "/Users/someone", "user home directory is not"),
            ("tildeHome", "/Users/someone", "tilde home is not"),
            ("support", "/Users/someone/Library/Application Support/Zeus", "support directory is not \(Self.root)/support"),
            ("temp", "/private/var/folders/xx/yyyy/T/", "temporary directory is not under"),
            ("temp", Self.root + "-evil/tmp/", "temporary directory is not under"),
            ("temp", Self.root + "/tmpx/", "temporary directory is not under"),
            ("temp", Self.root + "/home/", "temporary directory is not under"),
        ]
        for item in cases {
            let reason = StartupPolicy.verifyPaths(observation { $0[item.key] = item.value }, root: Self.root)
            #expect(reason?.contains(item.reason) == true, "\(item.key)=\(item.value): \(reason ?? "nil")")
        }
    }

    @Test func verifyRootNamesEachFailure() {
        func reason(_ dir: Bool, _ owner: Bool, _ marker: Bool) -> String? {
            StartupPolicy.verifyRoot(.init(isDirectory: dir, ownerMatches: owner, markerIsRegularFile: marker))
        }
        #expect(reason(true, true, true) == nil)
        #expect(reason(false, true, true)?.contains("not a real directory") == true)
        #expect(reason(false, false, false)?.contains("not a real directory") == true)
        #expect(reason(true, false, true)?.contains("not owned by this user") == true)
        #expect(reason(true, true, false)?.contains(StartupPolicy.markerFileName) == true)
    }

    @Test func fullGUIQAIsUnsupportedAndProbeExitsZero() {
        #expect(StartupPolicy.fullGUIQASupported == false)
        #expect(StartupPolicy.probeExitCode == 0)
        #expect(StartupPolicy.probeBoundaryLine.contains("not OS isolation"))
    }

    @Test func artifactBindingSeams() {
        #expect(StartupPolicy.requiredBundleIdentifier == "app.zeus.mac")
        #expect(StartupPolicy.isSHA256Hex(Self.digest))
        for bad in ["", String(Self.digest.uppercased()), String(Self.digest.dropLast()), Self.digest + "0",
                    String(repeating: "g", count: 64)] {
            #expect(!StartupPolicy.isSHA256Hex(bad), "\(bad)")
        }
    }

    @Test func manifestJSONIsCompactSortedAndVersioned() {
        #expect(StartupPolicy.manifestFormatVersion == "zeus-manifest-v1")
        let other = String(repeating: "1", count: 64)
        let json = StartupPolicy.manifestJSON(["Contents/b": other, "Contents/MacOS/Zeus": Self.digest, "Contents/Info.plist": other])
        #expect(json == "{\"Contents/Info.plist\":\"\(other)\",\"Contents/MacOS/Zeus\":\"\(Self.digest)\",\"Contents/b\":\"\(other)\"}")
        #expect(StartupPolicy.manifestJSON([:]) == "{}")
        #expect(StartupPolicy.manifestJSON(["a\"b": Self.digest]) == nil)
        #expect(StartupPolicy.manifestJSON(["a\\b": Self.digest]) == nil)
        #expect(StartupPolicy.manifestJSON(["a\nb": Self.digest]) == nil)
        #expect(StartupPolicy.manifestJSON(["/abs": Self.digest]) == nil)
        #expect(StartupPolicy.manifestJSON(["a": "xyz"]) == nil)
    }

    @Test func qaAcceptsNoArgumentsBeyondFlagAndRoot() {
        assertInvalid(decide(["--qa-startup", Self.root, "-topBar.note", "x"]), reason: "takes no other arguments")
        assertInvalid(decide(["--qa-startup", Self.root, "-zeus.qa.canary", Self.digest]), reason: "takes no other arguments")
        assertInvalid(decide(["-NSDocumentRevisionsDebugMode", "YES", "--qa-startup", Self.root]), reason: "takes no other arguments")
        assertInvalid(decide(["--qa-startup", Self.root, "extra"]), reason: "takes no other arguments")
        #expect(decide().mode == .qa(root: Self.root))
    }

    @Test func normalIgnoresRetiredCanaryEnvironment() {
        let normal = StartupPolicy.decide(arguments: ["Zeus"], environment: ["ZEUS_QA_DEFAULTS_CANARY": "junk"],
                                          launchTemporaryDirectory: "", realHome: "")
        #expect(normal == .normal)
        #expect(!StartupPolicy.requiredEnvironment(root: Self.root).keys.contains("ZEUS_QA_DEFAULTS_CANARY"))
    }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Reads the launcher as text only, from its repository path; never runs it.
    @Test func launcherScriptIsInspectOnlyAndBound() throws {
        let script = try String(contentsOf: Self.repository.appendingPathComponent("scripts/qa-startup-launch.sh"), encoding: .utf8)
        for needle in ["set -euo pipefail", "PATH=/usr/bin:/bin", "unset BASH_ENV ENV CDPATH", "--exec) die",
                       "--expect-binary-sha256", "--expect-manifest-sha256", "app.zeus.mac", "shasum -a 256", "! -L \"$current\"",
                       "zeus-manifest-v1", "stat -f '%u %Lp'", "find \"$app\" -type f -print0", "sort -z"] {
            #expect(script.contains(needle), "missing \(needle)")
        }
        for banned in ["/bin/ps", "ZEUS_QA_DEFAULTS_CANARY", "mktemp", "env -i", "kill", "trap ", "set -m", "wait ", "sleep",
                       "pgrep", "pkill", "killall", "defaults write", "defaults delete", "open -a", "launchctl", "tccutil",
                       "security", "rm -rf", "sudo", "curl", "$binary\" --qa-startup", "&\n", "${ZEUS", "exit 0"] {
            #expect(!script.contains(banned), "contains \(banned)")
        }
        let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!lines.contains { $0.hasPrefix("exec ") }, "no exec builtin")
        // The --exec refusal and the bundle identifier check come before any hashing.
        if let refusal = script.range(of: "--exec) die"), let identifier = script.range(of: "\"$bundle_id\" = \"app.zeus.mac\""),
           let hashing = script.range(of: "binary_hash=$(file_hash") {
            #expect(refusal.lowerBound < identifier.lowerBound)
            #expect(identifier.lowerBound < hashing.lowerBound)
        } else {
            Issue.record("missing refusal, bundle identifier check or hashing")
        }
    }

    /// Reads main.swift as text only: the `.qa` case must exit before any preference or AppKit consumer.
    @Test func mainQABlockExitsBeforeAnyConsumer() throws {
        let main = try String(contentsOf: Self.repository.appendingPathComponent("Sources/Zeus/App/main.swift"), encoding: .utf8)
        guard let start = main.range(of: "case .qa(let root):"),
              let end = main.range(of: "if !startupPolicy.isQA {", range: start.upperBound..<main.endIndex) else {
            Issue.record("cannot find the case .qa block")
            return
        }
        let block = String(main[start.upperBound..<end.lowerBound])
        for banned in ["UserDefaults", "Bundle.main", "NSRunningApplication", "NSApplication", "AppDelegate", "Process("] {
            #expect(!block.contains(banned), "case .qa contains \(banned)")
        }
        #expect(block.contains("exit(StartupPolicy.probeExitCode)"))
        if let exitAt = main.range(of: "exit(StartupPolicy.probeExitCode)"), let app = main.range(of: "let app = NSApplication.shared") {
            #expect(exitAt.lowerBound < app.lowerBound)
        } else {
            Issue.record("missing probe exit or NSApplication.shared")
        }
    }

    @Test func existingStartupModeResultsUnchanged() {
        #expect(ZeusStartupMode.resolve(arguments: ["Zeus"], isDebugBuild: true) == .normal)
        #expect(ZeusStartupMode.resolve(arguments: ["Zeus", "--jev-settings-test"], isDebugBuild: true) == .jevSettingsTest)
        #expect(ZeusStartupMode.resolve(arguments: ["Zeus", "--jev-settings-test"], isDebugBuild: false) == .unsupportedJevSettingsTest)
    }
}
