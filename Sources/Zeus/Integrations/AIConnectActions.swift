import AppKit
import ZeusCore

/// The one primary button per AI row (Settings › Integrations): Install, Sign in, Connect, Open,
/// Start or Test, whichever comes next for that provider (`AIConnectFlow`). Every action leaves
/// one status line in `messages`. Nothing here installs software, signs in for Tony or spends a
/// token: installers are only shown, logins run in Terminal for Tony to finish, and the checks
/// are the CLIs' own auth-status subcommands, local files and loopback ports.
extension AIConnections {
    func facts(_ provider: AIProvider, services: OnboardingServices) -> AIConnectFacts {
        var facts = AIConnectFacts(installed: installed(provider))
        switch provider.kind {
        case .hooked:
            facts.signedIn = signedIn[provider]
            if case .connected = status(provider, services: services) { facts.linked = true }
        case .app:
            facts.linked = UserDefaults.standard.bool(forKey: enabledKey(provider))
            facts.running = Self.isRunning(appNames: provider.appNames)
        case .localServer:
            facts.running = serverModels[provider] != nil
        case .endpoint:
            facts.configured = anyLLM.isComplete
            if case .passed = anyLLMTest { facts.testPassed = true }
            if case .failed = anyLLMTest { facts.testPassed = false }
        }
        return facts
    }

    func step(_ provider: AIProvider, services: OnboardingServices) -> AIConnectStep {
        AIConnectFlow.step(for: provider, facts: facts(provider, services: services))
    }

    /// The primary button.
    func primary(_ provider: AIProvider, services: OnboardingServices) {
        let step = step(provider, services: services)
        messages[provider] = nil
        switch step {
        case .install:
            installShown = installShown == provider ? nil : provider
            messages[provider] = AIConnectFlow.installCommand(provider) == nil
                ? "Download it from the official page, then click Check again."
                : "Run the command below in Terminal, then click Check again. Zeus never installs anything itself."
        case .signIn:
            signIn(provider)
        case .connect:
            Task { await connectAndCheck(provider, services: services) }
        case .openApp:
            openApp(provider, services: services)
        case .startServer:
            Task { await startServer(provider) }
        case .configure:
            messages[provider] = "Add a base URL and a model below, or pick OpenAI or Anthropic, then paste a key."
        case .test:
            Task { await testEndpoint() }
        case .connected:
            break
        }
    }

    // MARK: Sign in

    /// Opens Terminal with the CLI's own login for Tony to finish, then watches for the sign-in
    /// with the free status check for a few minutes.
    func signIn(_ provider: AIProvider) {
        guard let path = detections[provider]?.cliPath,
              let script = AIConnectFlow.signInScript(provider, executable: path) else {
            messages[provider] = "Zeus can't find the \(provider.binary ?? provider.title) command. Click Check again."
            return
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-signin-\(provider.rawValue).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        } catch {
            messages[provider] = "Couldn't prepare the sign-in: \(error.localizedDescription)"
            return
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", file.path]
        do { try open.run() } catch {
            messages[provider] = "Couldn't open Terminal: \(error.localizedDescription)"
            return
        }
        let shown = ([provider.binary ?? ""] + (AIConnectFlow.loginArguments(provider) ?? [])).joined(separator: " ")
        messages[provider] = "Terminal is open with \(shown). Finish signing in there; this row updates when you're in."
        signInWatch[provider]?.cancel()
        signInWatch[provider] = Task { @MainActor [weak self] in
            for _ in 0..<60 { // about five minutes
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                if await self.checkSignIn(provider) == true {
                    self.messages[provider] = "Signed in to \(provider.title). Click Connect to finish."
                    return
                }
            }
        }
    }

    /// Asks the CLI whether it is signed in. Free: `claude auth status`, `codex login status`,
    /// `cursor-agent status`; Gemini's own files. nil when it can't tell.
    @discardableResult
    func checkSignIn(_ provider: AIProvider) async -> Bool? {
        var answer: Bool?
        if provider == .gemini {
            let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini")
            answer = AIConnectFlow.geminiSignedIn(
                oauthCredentialsExist: FileManager.default.fileExists(atPath: home.appendingPathComponent("oauth_creds.json").path),
                settings: try? Data(contentsOf: home.appendingPathComponent("settings.json")),
                environment: ProcessInfo.processInfo.environment)
        } else if let arguments = AIConnectFlow.statusArguments(provider), let path = detections[provider]?.cliPath {
            let result = await Self.run(path, arguments, timeout: 10)
            answer = AIConnectFlow.signedIn(provider, exitCode: result.status, output: result.output)
        }
        if let answer { signedIn[provider] = answer } else { signedIn[provider] = nil }
        return answer
    }

    /// Checks every installed CLI's sign-in (all free), for the page's first look.
    func checkAllSignIns() async {
        for provider in AIProvider.allCases where provider.kind == .hooked && installed(provider) {
            await checkSignIn(provider)
        }
    }

    // MARK: Connect

    /// Installs Zeus's hooks (the existing installers), then the free status check.
    func connectAndCheck(_ provider: AIProvider, services: OnboardingServices) async {
        busy.insert(provider)
        defer { busy.remove(provider) }
        connect(provider, services: services)
        let installMessage = messages[provider]
        let signed = await checkSignIn(provider)
        RouterSettings.shared.refresh()
        let hooked: Bool = { if case .connected = status(provider, services: services) { return true } else { return false } }()
        let brain = provider.routerEngine.map { " \($0.title) is also a brain choice in Intelligence." } ?? ""
        switch (hooked, signed) {
        case (true, false?):
            messages[provider] = "Hooks installed, but \(provider.title) isn't signed in. Click Sign in."
        case (true, _):
            messages[provider] = "Connected. Hooks installed and \(provider.title) is signed in." + brain
        case (false, _):
            messages[provider] = installMessage ?? "Couldn't install the hooks. Click Check again."
        }
    }

    // MARK: Apps

    func openApp(_ provider: AIProvider, services: OnboardingServices) {
        guard let path = detections[provider]?.appPath else {
            messages[provider] = "\(provider.title) isn't in Applications. Click Check again after installing it."
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                AIConnections.shared.messages[provider] = error.map { "Couldn't open \(provider.title): \($0.localizedDescription)" }
                    ?? "Connected. \(provider.title) is open and gets your questions from the notch."
            }
        }
        connect(provider, services: services)
    }

    static func isRunning(appNames: [String]) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in appNames.contains(app.localizedName ?? "") }
    }

    // MARK: Local servers

    /// Opens Ollama or LM Studio (or `ollama serve` / `lms server start` without the app), then
    /// probes the loopback port for a few seconds.
    func startServer(_ provider: AIProvider) async {
        busy.insert(provider)
        defer { busy.remove(provider) }
        let appInstalled = detections[provider]?.appPath != nil
        guard let start = AIConnectFlow.startCommand(provider, appInstalled: appInstalled) else { return }
        if let app = start.app {
            _ = await Self.run("/usr/bin/open", ["-a", app], timeout: 10)
        } else if let path = detections[provider]?.cliPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = start.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch {
                messages[provider] = "Couldn't start \(provider.title): \(error.localizedDescription)"
                return
            }
        }
        for _ in 0..<8 {
            try? await Task.sleep(for: .seconds(1))
            await refresh(only: provider)
            if serverModels[provider] != nil { break }
        }
        if let count = serverModels[provider] {
            messages[provider] = "Connected. \(provider.title) is running with \(count == 1 ? "1 model" : "\(count) models")."
        } else {
            messages[provider] = "\(provider.title) didn't answer on port \(provider.localPort ?? 0) yet. Give it a moment, then Check again."
        }
    }

    // MARK: Endpoint

    /// The existing free endpoint test (it lists models), after refusing a model larger than
    /// Haiku / mini size.
    func testEndpoint() async {
        if let problem = AIConnectFlow.endpointModelProblem(anyLLM.model) {
            anyLLMTest = .failed(problem)
            messages[.anyLLM] = problem
            return
        }
        UserDefaults.standard.set(true, forKey: enabledKey(.anyLLM))
        await testAnyLLM()
        switch anyLLMTest {
        case .passed(let text), .failed(let text): messages[.anyLLM] = text
        default: break
        }
    }

    func applyPreset(baseURL: String, model: String) {
        anyLLM.baseURL = baseURL
        anyLLM.model = model
        anyLLMTest = .idle
        messages[.anyLLM] = "Filled in. Paste your key, then Test."
    }

    // MARK: Process

    /// Runs a short status command with a time limit; output is stdout and stderr together.
    nonisolated static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async -> (status: Int32, output: String) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
            environment["ZEUS_INTERNAL"] = "1"
            environment["NO_COLOR"] = "1"
            environment["NO_OPEN_BROWSER"] = "1"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            let deadline = Date().addingTimeInterval(timeout)
            let watchdog = Task.detached {
                while process.isRunning, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
                if process.isRunning { process.terminate() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}
