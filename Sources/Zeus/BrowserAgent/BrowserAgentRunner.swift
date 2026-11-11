import AppKit
import ZeusCore

/// Drives `BrowserAgentLoop` in Tony's own Chrome through the ZEUS extension, or (Settings, Features,
/// Browser agent, or `zeus browse --separate`) in a separate browser-use browser (`BrowserUseBackend`).
/// Each step is a short
/// one-shot to the brain the router picks (the CLI logins Tony already has: Claude, Codex, Gemini,
/// Cursor Agent, Grok, Ollama; or the Any LLM endpoint), pinned to ModelCap's fast tier. A notch
/// card shows the goal, step n/max and what it is doing, with a Stop button; Esc or saying "stop"
/// ends it too. Risky steps always wait for Tony's yes on their own card; the rest go through the
/// per-site consent the indexed actions already use.
@MainActor
final class BrowserAgentRunner {
    static let shared = BrowserAgentRunner()
    static let sessionID = "zeus-browser-agent"

    weak var notch: NotchController?
    var chrome: ChromeActions?
    /// Speaks and captions a line (VoiceTurnController.say).
    var say: (String) -> Void = { _ in }

    private(set) var isRunning = false
    private let stopFlag = StopFlag()
    private var loopTask: Task<BrowserAgentOutcome, Never>?
    private var escMonitors: [Any] = []
    private var lastPage: BrowserAgentPage?
    private var lastChromeTarget: ChromeBridge.ActionTarget?
    private var approvedNext = false
    private var goal = ""

    /// Runs one goal to the end. nil when another run is already going.
    func start(goal rawGoal: String, speak: Bool, maxSteps: Int = BrowserAgentLoop.configuredMaxSteps,
               separate: Bool = false) async -> BrowserAgentOutcome? {
        guard !isRunning else { return nil }
        guard FeatureSettings.browserAgentEnabled() else {
            return finish(.failed("the browser agent is off. Turn it on in Settings, Features."), speak: speak)
        }
        let goal = rawGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return finish(.failed("there was no goal."), speak: speak) }
        let kind = Self.backendKind(forceSeparate: separate)
        guard let chrome, notch != nil else { return finish(.failed("Zeus isn't ready yet."), speak: speak) }
        if kind == .chrome {
            guard await ChromeBridge.isConnected() else {
                return finish(.failed(ChromeBridge.BridgeFailure.notConnected.errorDescription ?? "Chrome isn't connected."), speak: speak)
            }
        } else {
            // Nothing is downloaded here: Settings, Features, Browser agent has the Set up button.
            let status = await BrowserUseSetup.status()
            guard status.ready else {
                return finish(.failed("the separate browser isn't set up yet. Open Settings, Features, Browser agent and press Set up."), speak: speak)
            }
        }
        // A free auth-status check per CLI, once per launch, so a signed-out engine is skipped.
        if AIConnections.shared.signedIn.isEmpty { await AIConnections.shared.checkAllSignIns() }
        let brains = Self.brains(for: goal)
        guard !brains.isEmpty else {
            return finish(.failed("no AI is connected. Connect one in Settings, Integrations."), speak: speak)
        }

        isRunning = true
        stopFlag.set(false)
        self.goal = goal
        lastPage = nil
        lastChromeTarget = nil
        approvedNext = false
        log("start: \(goal) via \(brains.map(\.name).joined(separator: " → ")) in \(kind == .chrome ? "Chrome" : "the separate browser"), max \(maxSteps) steps")
        showCard(step: 0, maxSteps: maxSteps, action: kind == .chrome ? "Starting" : "Starting the separate browser")
        startEscWatch()

        var launched: BrowserUseBackend?
        if kind == .separate {
            do {
                launched = try await BrowserUseBackend.launch(allowedDomains: FeatureSettings.browserAgentAllowedDomains())
            } catch {
                stopEscWatch()
                isRunning = false
                return finish(.failed((error as? LocalizedError)?.errorDescription ?? "the separate browser didn't start."), speak: speak)
            }
        }
        // Stop pressed while the separate browser was starting: there is no loop to cancel yet, so close it now.
        if stopFlag.isSet {
            await launched?.close()
            stopEscWatch()
            isRunning = false
            return finish(.failed("you stopped it before it began."), speak: speak)
        }
        let separateBackend = launched

        let chain = BrainChain(brains)
        let flag = stopFlag
        let ports = BrowserAgentPorts(
            think: { prompt in try await chain.think(prompt) },
            observe: { @MainActor [weak self] in
                let page: BrowserAgentPage
                if let separateBackend {
                    page = try await separateBackend.observe()
                } else {
                    let snapshot = try await Self.observeSnapshot()
                    page = snapshot.page
                    self?.lastChromeTarget = snapshot.target
                }
                self?.lastPage = page
                return page
            },
            execute: { @MainActor [weak self] action in
                guard let self else { throw BridgeError(code: "stopped") }
                if let separateBackend { return try await separateBackend.execute(action) }
                return try await self.perform(action, chrome: chrome)
            },
            approve: { @MainActor [weak self] approval in
                await self?.approve(approval, speak: speak) ?? false
            },
            shouldStop: { flag.isSet },
            progress: { @MainActor [weak self] progress in
                self?.showCard(step: progress.step, maxSteps: progress.maxSteps, action: progress.action)
            }
        )
        let task = Task { () -> BrowserAgentOutcome in
            var loop = BrowserAgentLoop(goal: goal, maxSteps: maxSteps)
            return await loop.run(ports)
        }
        loopTask = task
        let outcome = await task.value
        loopTask = nil
        await separateBackend?.close()
        stopEscWatch()
        isRunning = false
        log("end: \(outcome.label) via \(await chain.currentName)")
        return finish(outcome, speak: speak)
    }

    /// `zeus browse --separate` wins, otherwise the Settings choice.
    static func backendKind(forceSeparate: Bool, defaults: UserDefaults = .standard) -> BrowserAgentBackendKind {
        forceSeparate ? .separate : FeatureSettings.browserAgentBackend(defaults: defaults)
    }

    /// Stop button, Esc, "stop", or `zeus cancel`.
    func stop() {
        guard isRunning else { return }
        stopFlag.set(true)
        loopTask?.cancel()
    }

    /// "stop" / "cancel" while the agent runs. True when it was meant for the agent.
    func handle(transcript: String) -> Bool {
        guard isRunning else { return false }
        let words = transcript.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let stops = ["stop", "stop it", "stop that", "cancel", "cancel that", "abort", "halt", "enough", "that's enough",
                     "stop browsing", "stop the browser", "zeus stop"]
        guard stops.contains(words) else { return false }
        stop()
        return true
    }

    // MARK: Steps

    private func perform(_ action: BrowserAgentAction, chrome: ChromeActions) async throws -> String? {
        let approved = approvedNext
        approvedNext = false
        switch action {
        case .wait(let ms):
            try? await Task.sleep(for: .milliseconds(min(max(ms, 0), BrowserAgentOp.maxWait)))
            return nil
        case .open(let url):
            do { _ = try await ChromeBridge.call("tab.open", ["url": .string(url)]) } catch let failure as ChromeBridge.BridgeFailure {
                throw BridgeError(code: failure.code, message: failure.errorDescription)
            }
            try? await Task.sleep(for: .milliseconds(900)) // capped: the next look waits for elements again
            return nil
        case .command(let command):
            let label = command.elementIndex.flatMap { lastPage?.element($0)?.text }
            let text = try await chrome.agentExecute(command, label: label, approved: approved, observedTarget: lastChromeTarget)
            if command.changesPage { try? await Task.sleep(for: .milliseconds(600)) }
            return text
        }
    }

    /// The active tab with its numbered elements. A page still loading gets two more short looks.
    static func observe() async throws -> BrowserAgentPage {
        try await observeSnapshot().page
    }

    private static func observeSnapshot() async throws -> (page: BrowserAgentPage, target: ChromeBridge.ActionTarget?) {
        var snapshot: (context: TabContext, target: ChromeBridge.ActionTarget?)?
        for attempt in 0..<3 {
            snapshot = await ChromeBridge.activeTabSnapshot(timeout: 3, elements: true)
            if snapshot?.context.elements?.isEmpty == false { break }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(500)) }
        }
        guard let snapshot else { throw BridgeError(code: BridgeError.notConnected, message: ChromeBridge.BridgeFailure.notConnected.errorDescription) }
        let tab = snapshot.context
        return (BrowserAgentPage(url: tab.url, title: tab.title, state: tab.elementsState, elements: tab.elements ?? []), snapshot.target)
    }

    /// Risky steps: Tony's yes on their own card, whatever the autonomy setting.
    private func approve(_ approval: BrowserAgentApproval, speak: Bool) async -> Bool {
        guard let notch else { return false }
        updateSession(status: .needsYou)
        if speak { say(ZeusVoiceLines.line(for: .approval, context: ["agent": "The browser agent"])) }
        let verdict = await notch.requestApproval(agent: "Zeus", project: approval.host, tool: "Browser agent",
                                                  command: "\(approval.summary) (\(approval.reason))", risk: .high,
                                                  timeout: .seconds(90), onTimeout: .deny)
        updateSession(status: .working)
        approvedNext = verdict == .allow
        return approvedNext
    }

    // MARK: Card and voice

    private func showCard(step: Int, maxSteps: Int, action: String) {
        guard let notch else { return }
        let project = "step \(step)/\(maxSteps) · \(goal.count > 48 ? String(goal.prefix(47)) + "…" : goal)"
        if let index = notch.model.sessions.firstIndex(where: { $0.id == Self.sessionID }) {
            notch.model.sessions[index].project = project
            notch.model.sessions[index].task = action
            notch.model.sessions[index].status = .working
        } else {
            notch.model.stopHandlers[Self.sessionID] = { BrowserAgentRunner.shared.stop() }
            notch.startSession(id: Self.sessionID, agent: "Browser agent", project: project, task: action)
        }
    }

    private func updateSession(status: NotchModel.Status) {
        guard let notch, let index = notch.model.sessions.firstIndex(where: { $0.id == Self.sessionID }) else { return }
        notch.model.sessions[index].status = status
    }

    @discardableResult
    private func finish(_ outcome: BrowserAgentOutcome, speak: Bool) -> BrowserAgentOutcome {
        let spoken: String = {
            if case .done(let answer) = outcome, answer.isEmpty { return ZeusVoiceLines.line(for: .ackDone) }
            return outcome.spokenText
        }()
        if let notch, notch.model.sessions.contains(where: { $0.id == Self.sessionID }) {
            notch.update(sessionID: Self.sessionID, status: outcome.succeeded ? .done : .idle,
                         task: outcome.succeeded ? "Done" : "Stopped: \(outcome.label)")
            notch.model.stopHandlers[Self.sessionID] = nil
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(6))
                guard !BrowserAgentRunner.shared.isRunning else { return }
                notch?.removeSession(id: Self.sessionID)
            }
        }
        AvatarStatus.shared.flash(outcome.succeeded ? .done : .error, for: 2)
        if speak { say(spoken) }
        return outcome
    }

    // MARK: Esc

    private func startEscWatch() {
        let handler: (NSEvent) -> Void = { event in
            if event.keyCode == 53 { MainActor.assumeIsolated { BrowserAgentRunner.shared.stop() } }
        }
        if AccessibilityGate.trusted, let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            escMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handler($0); return $0 }) {
            escMonitors.append(local)
        }
    }

    private func stopEscWatch() {
        escMonitors.forEach(NSEvent.removeMonitor)
        escMonitors.removeAll()
    }

    private func log(_ message: String) { NSLog("[ZEUS] browser agent: %@", message) }

    // MARK: Brains

    struct Brain: Sendable {
        let name: String
        let call: @Sendable (BrowserAgentPrompt) async throws -> String
    }

    /// The router's choice for the goal first, then the other installed engines for that kind of
    /// task (never a cloud one for a private goal), then the Any LLM endpoint. A CLI found signed
    /// out in Settings is skipped. Every launch uses ModelCap's fast tier.
    static func brains(for goal: String) -> [Brain] {
        let router = RouterSettings.shared
        let task = RouterTask.classify(goal)
        let decision = router.decide(task)
        var order: [RouterEngine] = decision.engine.map { [$0] } ?? []
        order += task.ranking.filter { !order.contains($0) && decision.skipped[$0] == nil }
        let signedIn = AIConnections.shared.signedIn
        let localModel = UserDefaults.standard.string(forKey: "router.ollamaModel") ?? "llama3.2"
        var brains: [Brain] = order.compactMap { engine in
            guard let path = router.installed[engine] else { return nil }
            if let provider = AIProvider.allCases.first(where: { $0.routerEngine == engine }), signedIn[provider] == false { return nil }
            return Brain(name: engine.title) { prompt in
                try await oneShot(path: path, arguments: BrowserAgentBrainLaunch.arguments(engine: engine, prompt: prompt.combined,
                                                                                         localModel: localModel))
            }
        }
        let connections = AIConnections.shared
        let config = connections.anyLLM
        if task != .privateLocal, config.isComplete, AIConnectFlow.endpointModelProblem(config.model) == nil,
           UserDefaults.standard.bool(forKey: connections.enabledKey(.anyLLM)) {
            let key = Keychain.get(AnyLLMConfig.keyAccount)
            brains.append(Brain(name: "Any LLM") { prompt in
                guard let request = config.request(prompt: prompt.user, key: key, system: prompt.system) else {
                    throw BridgeError(code: "failed", message: "The Any LLM endpoint isn't set up.")
                }
                let (data, response) = try await AnyLLMHTTPTransport.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300, let answer = AnyLLMConfig.answer(from: data) else {
                    throw BridgeError(code: "failed", message: "The Any LLM endpoint didn't answer.")
                }
                return answer
            })
        }
        return brains
    }

    /// One headless CLI answer, killed after `timeout` or when the run stops.
    nonisolated static func oneShot(path: String, arguments: [String], timeout: TimeInterval = 60) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = CLILocator.searchDirectories.joined(separator: ":")
        environment["ZEUS_INTERNAL"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let directory = ZeusPaths.runDirectory(turn: UUID())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        process.currentDirectoryURL = directory
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        defer { try? FileManager.default.removeItem(at: directory) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                process.terminationHandler = { finished in
                    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let errors = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    if finished.terminationStatus == 0, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        let line = errors.split(separator: "\n").first.map(String.init)
                            ?? output.split(separator: "\n").first.map(String.init) ?? "exit status \(finished.terminationStatus)"
                        continuation.resume(throwing: BridgeError(code: "brain_failed", message: String(line.prefix(200))))
                    }
                }
                do { try process.run() } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Tries the brains in order until one answers; after the first answer it sticks with that one.
actor BrainChain {
    private let brains: [BrowserAgentRunner.Brain]
    private var current = 0
    private var settled = false

    init(_ brains: [BrowserAgentRunner.Brain]) { self.brains = brains }

    var currentName: String { brains.indices.contains(current) ? brains[current].name : "none" }

    func think(_ prompt: BrowserAgentPrompt) async throws -> String {
        while true {
            let brain = brains[current]
            do {
                let reply = try await brain.call(prompt)
                settled = true
                return reply
            } catch {
                if Task.isCancelled || settled || current + 1 >= brains.count { throw error }
                NSLog("[ZEUS] browser agent: %@ failed (%@), trying %@", brain.name, String(describing: error), brains[current + 1].name)
                current += 1
            }
        }
    }
}

/// Set from the main actor, read by the loop between steps.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set(_ newValue: Bool) { lock.withLock { value = newValue } }
}
