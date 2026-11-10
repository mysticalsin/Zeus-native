import AppKit
import ZeusCore

/// What one turn did, for the `zeus` CLI.
struct TurnResult: Sendable {
    var spoken = ""
    var actions: [String] = []
    var problems: [String] = []
    var error: String?
    var cancelled = false

    static let nothingHeard = TurnResult(error: "I didn't hear anything.")
}

/// One voice turn: hold the key → listen (screens captured now) → release → transcript →
/// Claude streams back → tags fly the spark, sentences are spoken as they arrive.
/// If an approval card is open, a short "ok" / "no" answers it instead.
@MainActor
final class VoiceTurnController {
    private let buddy: BuddyController
    private let notch: NotchController
    private let speech: SpeechInput
    private let speaker: Speaker
    let brain: BrainProvider
    let chrome: ChromeActions

    private var listening = false
    private var screenshotsTask: Task<[ScreenShot], Never>?
    private var tabTask: Task<TabContext?, Never>?
    private var turnTask: Task<TurnResult, Never>?
    private var currentTurn: UUID?
    private var history: [Exchange] = []
    /// True from release (or a wake phrase) until the turn's work is done.
    private(set) var turnRunning = false
    /// When the recogniser last changed its live transcript (hands-free turns end on silence).
    private var lastPartialAt: ContinuousClock.Instant?
    private var liveWords = LiveWordsHUD()
    private var heardSomething = false
    private var handsFreeTask: Task<Void, Never>?
    /// Hands-free follow-ups after the wake word (O20): end after 90 s of silence, Esc, or ✕.
    private var wakeConversationActive = false
    /// The Murmure engine for this turn when "Use for voice commands too" is on; nil is Apple live.
    private var turnEngine: (any TranscriptionEngine)?
    /// Starts a brain during a 0.7 s pause. A changed phrase drops it.
    private let ahead = AheadRunner()

    init(buddy: BuddyController, notch: NotchController, brain: BrainProvider) {
        self.buddy = buddy
        self.notch = notch
        self.brain = brain
        chrome = ChromeActions(notch: notch)
        speech = SpeechInput()
        speaker = Speaker(languageCode: speech.localeIdentifier)
        speech.onLevel = { [weak buddy] level in
            Task { @MainActor in buddy?.model.audioLevel = level }
        }
        // Live partials warm the fast path up (rules, then a speculative Laya answer) and time
        // the end of a hands-free turn.
        speech.onPartial = { [weak self] text in
            Task { @MainActor in
                guard let self, self.listening else { return }
                self.lastPartialAt = .now
                self.heardSomething = !text.trimmingCharacters(in: .whitespaces).isEmpty
                self.liveWords.applyPartial(text)
                if !self.liveWords.visible.isEmpty {
                    self.buddy.showCaption(self.liveWords.visible)
                }
                FastPath.shared.partial(text)
                self.armAhead(text)
            }
        }
        FastActions.shared.onLateProblem = { [weak self] text in self?.say(text) }
        ClaudeFlags.warm()
        BrainLaunchWarm.registerWait {
            async let ollama: Void = OpenAICompatProvider.ollama().prewarm()
            async let anthropic: Void = AnthropicAPIProvider().prewarm()
            _ = await (ollama, anthropic)
        }
        Task { await BrainLaunchWarm.awaitIfNeeded() }
        BrainWarmScheduler.shared.start()
        Task { @MainActor in
            await BrainWarmActions.live.warmSelectedVoice()
        }
    }

    /// After the words sit still for 0.7 s, start the fastest brain. Commands stay on the instant path.
    private func armAhead(_ text: String) {
        ahead.partial(text) { [weak self] utterance, _ in
            guard let self, AheadBrain.canStart(utterance) else { return }
            // Same privacy rule and provider choice as the real turn, applied before any provider exists.
            let task = RouterTask.classify(utterance)
            guard let first = BrainLatencyBook.shared.ordered(
                RouterSettings.shared.brainCandidates(task: task, hasAnthropicKey: AnthropicAPIProvider.hasKey), id: \.id).first else { return }
            let request = BrainRequest(turn: UUID(), transcript: utterance, systemPrompt: ZeusPrompt.system, deep: false)
            self.ahead.begin(engineID: first.id, provider: first.provider, request: request)
        }
    }

    /// Something is going on: listening, a turn in flight, or speaking. The wake word waits.
    var isBusy: Bool { listening || turnRunning || speaker.isSpeaking }
    var speechLocale: String { speech.localeIdentifier }

    var isSpeaking: Bool { speaker.isSpeaking }
    var isListening: Bool { listening }
    var hasPendingApproval: Bool { notch.model.approval != nil }
    var voiceDescription: String { speaker.engineDescription }

    /// Menu › Stop Speaking (pressing the talk key also interrupts).
    func stopSpeaking() {
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        ahead.cancel()
        speaker.stop()
        SystemAudioDucker.end()
        wakeConversationActive = false
        buddy.model.captionVisible = false
        buddy.idle()
    }

    @discardableResult
    func press() -> Bool {
        // A new press always interrupts whatever ZEUS was doing.
        BrainWarmScheduler.shared.noteActivity()
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        ahead.cancel()
        speaker.stop()
        buddy.model.captionVisible = false
        liveWords.clear()

        turnEngine = DictationHub.shared.controller?.voiceEngine
        speech.recordsSamples = turnEngine != nil
        speech.contextualStrings = DictationVocabularyPrompt.terms(DictationHub.shared.controller?.vocabulary ?? Vocabulary())
        do {
            try speech.start()
        } catch {
            VoiceLog.logContent("error", error.localizedDescription, prefix: "can't start listening (mic \(VoicePermissions.mic), speech \(VoicePermissions.speech)): ")
            ZeusSound.play(.voiceError)
            if let cue = VoicePermissions.access.deniedCue, let pane = VoicePermissions.access.deniedPane {
                VoicePermissions.notifyDenied(cue, pane)
            } else {
                say("I can't hear you yet. Check that ZEUS has microphone and speech recognition access.")
            }
            return false
        }
        listening = true
        VoiceLog.log("listen", "started (recogniser \(speech.localeIdentifier))")
        ZeusSound.play(.listenStart)
        SystemAudioDucker.begin()
        lastPartialAt = nil
        heardSomething = false
        FastPath.shared.reset()
        liveWords.clear()
        buddy.model.audioLevel = 0
        buddy.listen()
        // Screens are captured while you talk, so the answer isn't waiting on them.
        screenshotsTask = Task { await ScreenCapture.captureAll() }
        // With Chrome in front, the extension reads the page you're looking at.
        let chromeInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
        tabTask = chromeInFront ? Task { await ChromeBridge.activeTab(elements: true) } : nil
        return true
    }

    func release() {
        guard listening else { return }
        listening = false
        VoiceLog.log("listen", "stopped")
        ZeusSound.play(.listenStop)
        SystemAudioDucker.end()
        handsFreeTask?.cancel()
        handsFreeTask = nil
        buddy.think()
        turnRunning = true
        turnTask = Task {
            let result = await finishTurn()
            turnRunning = false
            if wakeConversationActive, result.error == nil, !result.cancelled {
                handsFree()
            }
            return result
        }
    }

    /// "Hey Zeus, open Spotify": the request already heard by the wake-word listener runs as a
    /// voice turn at once. "Hey Zeus" alone opens a hands-free turn that ends when you stop talking.
    func wakeTurn(request: String) {
        guard !listening else { return }
        wakeConversationActive = true
        buddy.call()
        let request = Self.dropWakeEchoes(request.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !request.isEmpty else { VoiceLog.log("wake", "no request after the phrase: listening hands-free"); handsFree(); return }
        VoiceLog.logContent("wake", request, prefix: "same-breath request: ")
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        speaker.stop()
        buddy.model.captionVisible = false
        let heardAt = ContinuousClock.now
        // Only the LLM path uses these; the fast path never waits for them.
        screenshotsTask = Task { await ScreenCapture.captureAll() }
        let chromeInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
        tabTask = chromeInFront ? Task { await ChromeBridge.activeTab(elements: true) } : nil
        buddy.think()
        turnRunning = true
        turnTask = Task {
            let result = await complete(transcript: request, finalAt: heardAt)
            turnRunning = false
            if wakeConversationActive, result.error == nil, !result.cancelled {
                handsFree()
            }
            return result
        }
    }

    /// A voice turn without the key: starts listening and stops after quiet once you have spoken.
    func handsFree() {
        guard press() else { return }
        let opened = ContinuousClock.now
        let silenceLimit: Duration = wakeConversationActive ? .seconds(WakeConversationTiming.silenceAfterSpeech) : .milliseconds(1000)
        let idleLimit: Duration = wakeConversationActive ? .seconds(WakeConversationTiming.silenceWhenEmpty) : .seconds(4)
        let hardLimit: Duration = wakeConversationActive ? .seconds(WakeConversationTiming.hardLimit) : .seconds(12)
        handsFreeTask = Task { @MainActor [weak self] in
            while let self, self.listening, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = ContinuousClock.now
                let quietFor = self.lastPartialAt.map { now - $0 } ?? (now - opened)
                if self.heardSomething ? quietFor > silenceLimit : quietFor > idleLimit { break }
                if now - opened > hardLimit { break }
            }
            guard let self, !Task.isCancelled, self.listening else { return }
            self.release()
        }
    }

    /// `zeus listen`: a hands-free voice turn of up to `seconds`, as if the talk key were held.
    func listenTurn(seconds: Double) async -> TurnResult {
        guard press() else {
            return TurnResult(error: "ZEUS can't hear yet: microphone or speech recognition access is missing.")
        }
        try? await Task.sleep(for: .seconds(max(1, min(seconds, 60))))
        if listening { release() }
        return await turnTask?.value ?? .nothingHeard
    }

    /// `zeus "..."`: a typed turn through the same fast path, brain, tags, actions and approvals as a spoken one.
    func textTurn(_ text: String, turn: UUID, deep: Bool, speak: Bool) async -> TurnResult {
        var screenshots: [ScreenShot] = []
        if ScreenAwareness.isScreenQuestion(text) {
            screenshots = await ScreenCapture.captureAll()
        }
        return await deliver(transcript: text, finalAt: .now, screenshots: screenshots, activeTab: nil, turn: turn,
                             deep: deep, speak: speak, awaitActions: true, loadCaptures: false)
    }

    /// Show-me: the marked screenshot plus where the mark is, answered aloud.
    func annotationTurn(_ prompt: String, screenshots: [ScreenShot]) async -> TurnResult {
        let turn = UUID()
        currentTurn = turn
        let result = await runTurn(transcript: prompt, screenshots: screenshots, activeTab: nil, turn: turn,
                                   deep: false, speak: true, awaitActions: false)
        if currentTurn == turn { currentTurn = nil }
        return result
    }

    func cancel(turn: UUID) {
        Task { await brain.cancel(turn: turn) }
    }

    private func finishTurn() async -> TurnResult {
        var transcript = await speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        if let engine = turnEngine, let dictation = DictationHub.shared.controller {
            let samples = speech.takeSamples()
            transcript = await dictation.transcribeVoice(samples: samples, live: transcript, with: engine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        turnEngine = nil
        buddy.model.audioLevel = nil
        return await complete(transcript: transcript, finalAt: .now)
    }

    /// A finished transcript: approval answers, walkthrough steering, the fast path, then the LLM.
    private func complete(transcript: String, finalAt: ContinuousClock.Instant) async -> TurnResult {
        guard !Task.isCancelled else { return TurnResult(cancelled: true) }
        guard !transcript.isEmpty else {
            VoiceLog.log("transcript", "(nothing heard)")
            buddy.idle()
            return .nothingHeard
        }
        VoiceLog.logContent("transcript", transcript)

        let options = SettingsStore.shared
        if let approval = notch.model.approval, options.bool("voice.answers"),
           let verdict = ApprovalPhrases.verdict(for: transcript, approve: options.words("voice.approveWords"),
                                                 deny: options.words("voice.denyWords"), open: options.words("voice.openWords")) {
            approval.resolve(verdict)
            buddy.idle()
            let answer = verdict == .allow ? "Approved." : verdict == .ask ? "Over to the app." : "Denied."
            say(answer)
            return TurnResult(spoken: answer)
        }

        // "stop" ends a running browser agent, no model call.
        if BrowserAgentRunner.shared.handle(transcript: transcript) {
            buddy.idle()
            return TurnResult(spoken: "")
        }

        // "next", "back", "stop" steer a running walkthrough, no model call.
        if WalkthroughController.shared.handle(transcript: transcript) {
            buddy.idle()
            return TurnResult(spoken: "")
        }

        if let spoken = await LearnedSteps.handle(transcript) {
            buddy.idle()
            say(spoken)
            return TurnResult(spoken: spoken)
        }
        if let selected = TextInserter.selectedText(),
           let edit = SelectionRewrite.plan(utterance: transcript, selection: selected) {
            HandsHUD.shared.present(edit, notch: notch)
            buddy.idle()
            return TurnResult(spoken: "")
        }

        // Instant commands act before anything waits on the screenshots, the tab or the AX snapshot.
        let turn = UUID()
        currentTurn = turn
        let result = await deliver(transcript: transcript, finalAt: finalAt, screenshots: [], activeTab: nil,
                                   turn: turn, deep: false, speak: true, awaitActions: false, loadCaptures: true)
        if currentTurn == turn { currentTurn = nil }
        return result
    }

    /// Instant answers, then the fast path, then the brain. Screenshots load only when a model is needed.
    private func deliver(transcript: String, finalAt: ContinuousClock.Instant, screenshots: [ScreenShot],
                         activeTab: TabContext?, turn: UUID, deep: Bool, speak: Bool, awaitActions: Bool,
                         loadCaptures: Bool) async -> TurnResult {
        let route = InstantTable.route(transcript)
        if case .files(let query) = route {
            return await openFound(query, transcript: transcript, speak: speak)
        }
        if case .mixed(let command, let rest) = route {
            _ = await understand(command, finalAt: finalAt, speak: speak)
            return await runTurn(transcript: rest, screenshots: [], activeTab: activeTab, turn: turn,
                                 deep: deep, speak: speak, awaitActions: awaitActions, pageText: true)
        }
        if case .web(let query) = route, let url = URL(string: query), let page = await PageFetch.text(from: url) {
            let told = "Page text:\n\(page)\n\n\(transcript)"
            return await runTurn(transcript: told, screenshots: [], activeTab: activeTab, turn: turn,
                                 deep: deep, speak: speak, awaitActions: awaitActions, pageText: true)
        }
        if let replay = ahead.take(matching: transcript) {
            return await runTurn(transcript: transcript, screenshots: [], activeTab: activeTab, turn: turn,
                                 deep: deep, speak: speak, awaitActions: awaitActions, replay: replay,
                                 pageText: !InstantTable.allowsScreenshots(route))
        }
        if let handled = await understand(transcript, finalAt: finalAt, speak: speak) { return handled }
        let shots: [ScreenShot]
        let tab: TabContext?
        if loadCaptures {
            let captured = await screenshotsTask?.value ?? []
            shots = InstantTable.allowsScreenshots(route) ? captured : []
            tab = chrome.prepare(await tabTask?.value)
        } else {
            shots = InstantTable.allowsScreenshots(route) ? screenshots : []
            tab = activeTab
        }
        return await runTurn(transcript: transcript, screenshots: shots, activeTab: tab, turn: turn,
                             deep: deep, speak: speak, awaitActions: awaitActions,
                             pageText: !InstantTable.allowsScreenshots(route))
    }

    private func speakInstant(_ answer: String, transcript: String, speak: Bool) -> TurnResult {
        VoiceLog.log("route", "rules")
        VoiceLog.log("brain", "engine=local model=none first_token_ms=0 done_ms=0")
        buddy.idle()
        if speak { say(answer) } else { buddy.showCaption(answer); buddy.hideCaption() }
        remember(transcript, answer)
        return TurnResult(spoken: answer)
    }

    private func openFound(_ query: String, transcript: String, speak: Bool) async -> TurnResult {
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        let started = Date()
        let paths = await Task.detached(priority: .userInitiated) { SpotlightClient.paths(matching: query) }.value
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        VoiceLog.log("route", "rules")
        VoiceLog.log("brain", "engine=local model=none first_token_ms=\(ms) done_ms=\(ms)")
        guard let path = SpotlightQuery.pick(paths: paths, query: query) else {
            let missing = "I couldn't find that."
            buddy.idle()
            if speak { say(missing) } else { buddy.showCaption(missing); buddy.hideCaption() }
            remember(transcript, missing)
            return TurnResult(spoken: missing)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let answer = "Opening \(name)."
        buddy.idle()
        if speak { say(answer) } else { buddy.showCaption(answer); buddy.hideCaption() }
        remember(transcript, answer)
        return TurnResult(spoken: answer, actions: ["files \(path)"])
    }

    /// Everything answered without the LLM, in order: local rules (`FastIntent`), the to-do and
    /// brief phrases (`LocalTurns`), then the decision engine (Laya, Jev). nil means "LLM".
    private func understand(_ transcript: String, finalAt: ContinuousClock.Instant, speak: Bool) async -> TurnResult? {
        let fast = FastPath.shared
        switch fast.rules(transcript) {
        case .hit(let plan, let engine): return await perform(plan, engine: engine, transcript: transcript, finalAt: finalAt, speak: speak)
        case .ask(let question, let engine): return askBack(question, engine: engine, transcript: transcript, speak: speak)
        case .miss: break
        }
        if let answer = PersonaQueries.localAnswer(for: transcript) {
            return speakInstant(answer, transcript: transcript, speak: speak)
        }
        if let memoryReply = handleMemory(transcript, speak: speak) {
            return memoryReply
        }
        if let brainReply = handleSecondBrain(transcript, speak: speak) {
            return brainReply
        }
        if let watchReply = handleWatch(transcript, speak: speak) {
            return watchReply
        }
        if let routineReply = handleRoutineVoice(transcript, speak: speak) {
            return routineReply
        }
        // To-dos and the daily brief are answered on the Mac, no model call.
        if let local = await LocalTurns.handle(transcript, topBar: notch.topBar) {
            return speakInstant(local, transcript: transcript, speak: speak)
        }
        // "Ask Scout to ..." goes to that agent, not to command understanding.
        if AgentRouter.route(transcript, agents: AgentStore().profiles()) != nil { return nil }
        guard !Task.isCancelled else { return TurnResult(cancelled: true) }
        switch await fast.engine(transcript) {
        case .hit(let plan, let engine): return await perform(plan, engine: engine, transcript: transcript, finalAt: finalAt, speak: speak)
        case .ask(let question, let engine): return askBack(question, engine: engine, transcript: transcript, speak: speak)
        case .miss: return nil
        }
    }

    /// Runs a fast action. The action starts first; the spoken ack follows in parallel.
    private func perform(_ plan: FastActions.Plan, engine: String, transcript: String,
                         finalAt: ContinuousClock.Instant, speak: Bool) async -> TurnResult {
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        let fast = FastPath.shared
        let interval = fast.signposter.beginInterval("fast action", "\(plan.intent.intentLabel, privacy: .public)")
        buddy.idle()
        let problem = await plan.run { [weak self] in
            let elapsed = FastPath.ms(ContinuousClock.now - finalAt)
            fast.signposter.emitEvent("action started", "\(elapsed, format: .fixed(precision: 1), privacy: .public) ms")
            VoiceLog.log("route", "fast via \(engine): \(plan.intent.intentLabel)")
            VoiceLog.log("action", "\(VoiceLog.described(plan.summary)) started \(String(format: "%.0f", elapsed)) ms after the transcript")
            IntelligenceCenter.shared.announce(engine: engine, summary: plan.summary)
            AvatarStatus.shared.flash(.done, for: 1.5)
            if let ack = plan.ack, !ack.isEmpty, let self {
                if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
            }
        }
        fast.signposter.endInterval("fast action", interval)
        // QA7 round 10: `plan.ack == nil` means "says nothing, the notch cue is enough" (see
        // `AckLines.rawNeutral`'s `.media`/`.volume`/`.locking` cases) -- `say()` is correctly
        // never called for those below, but this field used to fall back to `plan.summary`
        // ("Play", a bare verb) and report it as if it had been spoken. Report what was actually
        // said, which is nothing.
        var result = TurnResult(spoken: plan.ack ?? "", actions: ["fast \(plan.intent.intentLabel) via \(engine): \(plan.summary)"])
        if let problem {
            result.problems.append(problem)
            AvatarStatus.shared.flash(.error, for: 2)
            VoiceLog.logContent("error", problem, prefix: "action problem: ")
            ZeusSound.play(.voiceError)
            let spoken = SpokenFailure.line(problem)
            if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
        }
        remember(transcript, plan.ack ?? plan.summary)
        if problem == nil { ZeusSound.play(.voiceDone) }
        return result
    }

    static let restrictedNote = "Screen capture and actions aren't allowed from the command line. Turn on 'Allow command-line control' in Settings ▸ Privacy."

    /// For a reply whose action tag was refused: the action was not run.
    static let blockedActionNote = "I didn't run that action. Command-line control is off. Turn on 'Allow command-line control' in Settings ▸ Privacy."

    private func refuseRestricted(speak: Bool) -> TurnResult {
        VoiceLog.log("action", "refused (command-line control off)")
        buddy.idle()
        let note = Self.restrictedNote
        if speak { say(note) } else { buddy.showCaption(note); buddy.hideCaption() }
        var result = TurnResult(spoken: note)
        result.problems.append(note)
        return result
    }

    /// Not sure which one you meant: ask instead of guessing.
    private func askBack(_ question: String, engine: String, transcript: String, speak: Bool) -> TurnResult {
        VoiceLog.logContent("route", question, prefix: "fast via \(engine) asks: ")
        buddy.idle()
        if speak { say(question) } else { buddy.showCaption(question); buddy.hideCaption() }
        remember(transcript, question)
        return TurnResult(spoken: question)
    }

    private func remember(_ user: String, _ assistant: String) {
        history.append(Exchange(user: user, assistant: assistant))
        if history.count > 10 { history.removeFirst(history.count - 10) }
    }

    private func handleSecondBrain(_ transcript: String, speak: Bool) -> TurnResult? {
        guard let topic = BrainRecall.topic(from: transcript), let vault = connectedBrainVault(),
              SecondBrain.looksLikeVault(vault) else { return nil }
        let answer = BrainRecall.spokenAnswer(vault: vault, topic: topic)
        VoiceLog.log("route", "second-brain")
        return speakInstant(answer, transcript: transcript, speak: speak)
    }

    private func connectedBrainVault() -> URL? {
        if let path = TodoController.shared.connection?.source.path {
            return URL(fileURLWithPath: path)
        }
        if let env = ProcessInfo.processInfo.environment["ZEUS_BRAIN_FIXTURE"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return BrainToday.defaultRoot()
    }

    private func handleMemory(_ transcript: String, speak: Bool) -> TurnResult? {
        guard let cmd = UserMemoryCommands.parse(transcript) else { return nil }
        let persistence = UserMemoryPersistence.shared
        var reply: String
        // Logged instead of the reply: the reply can quote stored personal memories.
        var logOutcome = "handled"
        do {
            // A file that can't be read is never treated as empty: nothing is changed or saved.
            var store = try persistence.loadChecked()
            var changed = false
            switch cmd.kind {
            case .remember(let text):
                switch store.rememberRule(text) {
                case .storedRule, .storedFact:
                    reply = "Got it. I'll remember that."
                    changed = true
                case .rejectedSensitive: reply = "I can't store sensitive things like that."
                case .rejectedScreenSource: reply = "I only remember what you tell me, not what's on screen."
                }
            case .forget(let phrase):
                // "that" alone is the bare command; a named phrase never reaches here as "that".
                let outcome: UserMemoryStore.ForgetOutcome = phrase == "that"
                    ? .removed(store.forgetNewest()) : store.forgetOne(matching: phrase)
                switch outcome {
                case .removed(let removed):
                    reply = removed == 0 ? "I didn't find that." : "Forgot one item."
                    changed = removed > 0
                    logOutcome = removed == 0 ? "forget: none found" : "forget: removed \(removed)"
                case .needsChoice(let candidates):
                    // Never bulk-delete: list what matched and ask which one.
                    let listed = candidates.prefix(4).map { "\"\($0)\"" }.joined(separator: ", ")
                    reply = "That matches \(candidates.count) things: \(listed). Which one should I forget? Say it more exactly."
                    logOutcome = "forget: needs choice, \(candidates.count) matches"
                }
            }
            if changed {
                do { try persistence.save(store) } catch {
                    VoiceLog.logContent("error", error.localizedDescription, prefix: "memory save: ")
                    reply = "I couldn't save that, so nothing changed."
                    logOutcome = "save failed"
                }
            }
        } catch {
            VoiceLog.logContent("error", error.localizedDescription, prefix: "memory load: ")
            reply = "I can't read my memory file, so I left it alone."
            logOutcome = "load failed"
        }
        VoiceLog.log("memory", logOutcome)
        buddy.idle()
        if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
        remember(transcript, reply)
        return TurnResult(spoken: reply)
    }

    private func handleWatch(_ transcript: String, speak: Bool) -> TurnResult? {
        if transcript.lowercased().contains("stop watching") {
            ZeusWatchRunner.shared.stopAll()
            let reply = "Stopped watching."
            buddy.idle()
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            return TurnResult(spoken: reply)
        }
        guard let watch = ZeusWatchVoice.parse(transcript) else { return nil }
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        ZeusWatchRunner.shared.startWatch(watch)
        let reply = "I'll watch for that."
        buddy.idle()
        if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
        return TurnResult(spoken: reply)
    }

    private func handleRoutineVoice(_ transcript: String, speak: Bool) -> TurnResult? {
        guard let parsed = RoutineVoiceParse.parse(transcript) else { return nil }
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        let routine = Routine(name: parsed.name, prompt: parsed.prompt, schedule: parsed.schedule, engine: Routine.voiceDefaultEngine)
        RoutineRunner.shared.add(routine)
        let reply = "Routine saved."
        buddy.idle()
        if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
        return TurnResult(spoken: reply)
    }

    private func runTurn(transcript: String, screenshots: [ScreenShot], activeTab: TabContext?, turn: UUID,
                         deep: Bool, speak: Bool, awaitActions: Bool,
                         replay: (id: String, events: AsyncThrowingStream<BrainEvent, Error>)? = nil,
                         pageText: Bool = false) async -> TurnResult {
        // Named agents: "ask Scout to ...", "Scribe, ...". Each has its own persona and memory.
        let agentStore = AgentStore()
        let route = AgentRouter.route(transcript, agents: agentStore.profiles())
        if let route, let note = route.remember {
            var memory = agentStore.memory(for: route.agent)
            memory.remember(note, pinned: true)
            try? agentStore.save(memory, for: route.agent)
            let reply = "\(route.agent.name) will remember that."
            NSLog("[ZEUS] agent %@: pinned note (%d notes)", route.agent.name, memory.notes.count)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            return TurnResult(spoken: reply)
        }
        VoiceLog.log("route", "brain (LLM)\(route.map { ", agent \($0.agent.name)" } ?? "")")
        RouterSettings.shared.noteOllamaHTTPReachable(await OllamaHTTPProbe.isReachable())
        await BrainLaunchWarm.awaitIfNeeded()
        VoiceAnswerLatency.beginTurn()
        var system = ZeusPrompt.system
        let spokenTranscript = route?.request ?? transcript
        let includeFront = BrainTurnPrep.usesFrontContext(transcript: spokenTranscript)
        // A CLI turn without 'Allow command-line control': no screen, no window controls, no actions.
        let restricted = CLIAccess.turnRestricted
        let awareness = ScreenAwareness.plan(transcript: spokenTranscript,
                                             axSummary: includeFront ? Self.context(controls: !restricted) : nil,
                                             tab: activeTab)
        if pageText {
            system += "\n\nAnswer from the page text you were given. Do not use a screenshot."
        } else if !awareness.promptPrefix.isEmpty {
            system += "\n\n" + awareness.promptPrefix
            NSLog("[ZEUS] screen awareness: axTokens=%d preferPixels=%@", awareness.axTokenEstimate, awareness.preferPixels ? "yes" : "no")
        }
        let memoryBlock = UserMemoryPersistence.shared.load().promptBlock(for: transcript)
        if !memoryBlock.isEmpty { system += "\n\n" + memoryBlock }
        var shots = restricted ? [] : screenshots
        if !restricted, !pageText, awareness.needsCapture, shots.isEmpty {
            shots = await ScreenCapture.captureAll()
        }
        if pageText || restricted || (awareness.preferPixels == false && !awareness.promptPrefix.isEmpty) {
            shots = []
        }
        if let route {
            system += "\n\n" + AgentRouter.preamble(route.agent, memory: agentStore.memory(for: route.agent))
            NSLog("[ZEUS] agent %@: routed turn", route.agent.name)
        }
        var result = TurnResult()
        let request = BrainRequest(
            turn: turn,
            transcript: route?.request ?? transcript,
            screenshots: shots,
            axSummary: includeFront ? Self.context(controls: activeTab == nil && !restricted) : nil,
            activeTab: activeTab,
            history: history,
            systemPrompt: system,
            deep: deep
        )

        var parser = ZeusTagStreamParser()
        var splitter = SentenceSplitter()
        var spoken = ""
        var pointed = false
        var startedSpeaking = false
        var actionTasks: [Task<String?, Never>] = []
        // QA7 round 10: a degraded fallback brain leaked invented bracket tags, raw terminal
        // control codes and a hallucinated continuation of the conversation straight into speech
        // (see `ResponseSanitizer`'s own doc comment). Once a hallucinated turn is found, every
        // later chunk of this same reply is the model talking to itself, not to Tony.
        var haltedForHallucination = false
        let personaSentenceLimit = PersonaReplyClamp.maxSentences(transcript: transcript, personality: ZeusPersonality.current())
        var spokenSentenceCount = 0
        var haltedForPersonaLimit = false
        var blockedByRestriction = false

        func handle(_ output: ZeusTagStreamParser.Output) {
            switch output {
            case .tag(.point(let target?)):
                if let point = globalPoint(x: target.x, y: target.y, screen: target.screen, in: shots) {
                    buddy.point(to: point, label: target.label ?? "right here")
                    pointed = true
                }
            case .tag(.highlight(let area)):
                if let point = globalPoint(x: area.x + area.width / 2, y: area.y + area.height / 2,
                                           screen: area.screen, in: shots) {
                    buddy.point(to: point, label: area.label ?? "this area")
                    pointed = true
                }
            case .tag(.action(let action)):
                if restricted {
                    // Refused at the boundary: nothing is run, and the reply says so.
                    blockedByRestriction = true
                    VoiceLog.log("action", "tag \(action.kind) refused (command-line control off)")
                    break
                }
                // Runs alongside the spoken reply; a failure is said once the reply is done.
                result.actions.append(String(describing: action))
                VoiceLog.log("action", "tag \(action.kind)")
                AvatarStatus.shared.flash(Self.avatarState(for: action.kind), for: 3)
                let task: Task<String?, Never>
                switch action.kind {
                case .macDrive:
                    let plan = DrivePlan.parse(action.payload)
                    task = Task { @MainActor in
                        guard let plan else { return "That plan didn't make sense, so I left it." }
                        return await DriveController.shared.perform(plan, screenshots: shots)
                    }
                case .browserAgent:
                    // Runs on its own, step by step, with its notch card; it speaks the result.
                    let goal = action.payload["goal"]?.stringValue ?? ""
                    task = Task { @MainActor in
                        let runner = BrowserAgentRunner.shared
                        guard !runner.isRunning else { return "I'm already working on a web task. Say stop or press Esc to end it first." }
                        Task { @MainActor in _ = await runner.start(goal: goal, speak: speak) }
                        return nil
                    }
                case .terminalAgent, .terminalOpen, .terminalRun, .research:
                    // Terminal sessions, shell commands (approval card when risky) and research reports.
                    let command = CodeCommand(action)
                    task = Task { @MainActor in
                        guard let command else { return "I couldn't tell what to run, so I left it." }
                        let outcome = await CodeActions.shared.perform(command, speak: speak)
                        return outcome.ok ? nil : outcome.message
                    }
                case .macWalkthrough:
                    let tour = Walkthrough.parse(action.payload)
                    task = Task { @MainActor in
                        guard let tour else { return "I couldn't put that tour together." }
                        WalkthroughController.shared.start(tour, screenshots: shots)
                        return nil
                    }
                case .presentCard:
                    let card = PresentCard.parse(action.payload)
                    task = Task { @MainActor in
                        guard let card else { return nil }
                        let body = ([card.title] + card.lines).joined(separator: "\n")
                        self.buddy.showCaption(body)
                        self.buddy.hideCaption()
                        return nil
                    }
                default:
                    task = Task { [chrome] in await chrome.perform(action) }
                }
                actionTasks.append(task)
                if !awaitActions {
                    Task { [weak self] in
                        if let problem = await task.value { self?.say(SpokenFailure.line(problem)) }
                    }
                }
            case .tag(.point(nil)):
                break
            case .text(let text):
                guard !haltedForHallucination, !haltedForPersonaLimit else { break }
                var sanitizedDelta = ResponseSanitizer.stripArtifacts(text)
                // Checked against the full `spoken + sanitizedDelta` string so a hallucinated
                // "\nUser:"/"\nTony:" marker split across two streamed chunks is still caught.
                let priorLength = spoken.count
                let candidate = spoken + sanitizedDelta
                if let cut = ResponseSanitizer.hallucinatedTurnStart(in: candidate) {
                    let cutOffset = candidate.distance(from: candidate.startIndex, to: cut)
                    let deltaCutOffset = max(0, min(sanitizedDelta.count, cutOffset - priorLength))
                    let deltaCutIndex = sanitizedDelta.index(sanitizedDelta.startIndex, offsetBy: deltaCutOffset)
                    sanitizedDelta = String(sanitizedDelta[..<deltaCutIndex])
                    haltedForHallucination = true
                }
                guard !sanitizedDelta.isEmpty else { break }
                spoken += sanitizedDelta
                for sentence in splitter.feed(sanitizedDelta) {
                    guard spokenSentenceCount < personaSentenceLimit else {
                        haltedForPersonaLimit = true
                        break
                    }
                    spokenSentenceCount += 1
                    if !startedSpeaking, !pointed { buddy.idle() }
                    startedSpeaking = true
                    VoiceAnswerLatency.noteFirstSentence()
                    if speak { speaker.speak(PersonaCompliance.stripOminousHedges(sentence)) }
                    buddy.showCaption(Self.captionTail(spoken))
                }
            }
        }

        do {
            let started = Date()
            if let replay {
                VoiceLog.log("route", "brain speculative \(replay.id)")
                try await Self.consume(replay.events, engine: { replay.id }, started: started) { delta in
                    parser.feed(delta).forEach(handle)
                }
            } else {
                // The task's privacy rule and provider choice decide the candidates before any
                // provider (and so any request) is created; a private task never sees a cloud engine.
                let taskKind = RouterTask.classify(transcript)
                let candidates = BrainLatencyBook.shared.ordered(
                    RouterSettings.shared.brainCandidates(task: taskKind, hasAnthropicKey: AnthropicAPIProvider.hasKey, claude: brain),
                    id: \.id)
                VoiceLog.log("route", candidates.isEmpty ? "brain (none)" : "brain \(candidates.map(\.id).joined(separator: " > "))")
                guard !candidates.isEmpty else {
                    throw ClaudeCLIProvider.ProviderError.failed(
                        taskKind == .privateLocal ? "no local AI is available for a private request" : "no AI answered")
                }
                var deepNow = deep || ModelBudget.shouldEscalate(task: taskKind, failed: false)
                var cursor = 0
                var lastErrors: [String] = []
                // One provider at a time (sequential fallback) unless the person turned cloud racing on:
                // racing sends the full contextual request to several providers at once.
                let racing = UserDefaults.standard.bool(forKey: "opt.brain.cloudRacing")
                while cursor < candidates.count {
                    let end = min(cursor + (racing ? 4 : 1), candidates.count)
                    let slice = Array(candidates[cursor..<end])
                    let opened = Self.openBrains(slice, request: request.with(deep: deepNow))
                    do {
                        try await Self.consume(opened.events, engine: opened.engine, started: started) { delta in
                            parser.feed(delta).forEach(handle)
                        }
                        break
                    } catch where spoken.isEmpty && !Task.isCancelled {
                        let text = error.localizedDescription
                        if let engine = RouterEngine(rawValue: opened.engine()) {
                            if RouterSettings.isQuotaError(text) || RouterSettings.isSignInError(text) {
                                RouterSettings.shared.markExhausted(engine)
                            } else if RouterSettings.isTimeoutError(text) {
                                RouterSettings.shared.markExhausted(engine, for: 10 * 60)
                            }
                        }
                        lastErrors.append(text)
                        for racer in slice { BrainLatencyBook.shared.recordFailure(racer.id) }
                        VoiceLog.logContent("route", text, prefix: "\(opened.engine()) failed; detail ")
                        cursor += slice.count
                        deepNow = true
                        if cursor >= candidates.count {
                            throw ClaudeCLIProvider.ProviderError.failed(Self.allEnginesFailed(lastErrors))
                        }
                    }
                }
            }
            parser.finish().forEach(handle)
            if let rest = splitter.flush(), speak { speaker.speak(PersonaCompliance.stripOminousHedges(rest)) }
            buddy.showCaption(Self.captionTail(spoken))
            buddy.hideCaption()
            if !pointed { buddy.idle() }
            if !result.actions.isEmpty { AvatarStatus.shared.flash(.done, for: 2) }
            // Defense in depth: a tag or control code split oddly across streamed chunks could
            // dodge the per-chunk pass above; run it once more now that the full reply is in hand.
            let personality = ZeusPersonality.current()
            let answer = PersonaReplyClamp.clamp(ResponseSanitizer.sanitize(spoken), transcript: transcript, personality: personality)
            if answer.isEmpty { VoiceLog.log("spoken", "(nothing)") } else { VoiceLog.logContent("spoken", answer) }
            ZeusSound.play(.voiceDone)
            if let route, !answer.isEmpty {
                var memory = agentStore.memory(for: route.agent)
                memory.remember("Asked: \(route.request.prefix(160)) / Answered: \(answer.prefix(200))")
                try? agentStore.save(memory, for: route.agent)
            }
            if !answer.isEmpty {
                history.append(Exchange(user: transcript, assistant: answer))
                if history.count > 10 { history.removeFirst(history.count - 10) }
            }
        } catch {
            guard !Task.isCancelled else { return TurnResult(cancelled: true) }
            buddy.idle()
            let message = Self.spokenError(error)
            VoiceLog.logContent("error", error.localizedDescription, prefix: "brain: ")
            ZeusSound.play(.voiceError)
            AvatarStatus.shared.flash(.error, for: 3)
            result.error = message
            if speak { say(message) } else { buddy.showCaption(message); buddy.hideCaption() }
        }
        result.spoken = PersonaReplyClamp.clamp(ResponseSanitizer.sanitize(spoken), transcript: transcript,
                                                 personality: ZeusPersonality.current())
        if blockedByRestriction {
            // Said and captioned once (the flag is per turn), and the delivered answer says nothing ran.
            let note = Self.blockedActionNote
            if speak { say(note) } else { buddy.showCaption(note); buddy.hideCaption() }
            result.spoken = result.spoken.isEmpty ? note : result.spoken + " " + note
            result.problems.append(note)
        }
        if awaitActions {
            for task in actionTasks {
                if let problem = await task.value { result.problems.append(problem) }
            }
        }
        return result
    }

    /// Frontmost app and the local time, so "what time is it" and "this app" need no tools.
    /// The frontmost app, the time and, with `controls`, a fresh snapshot of the front window's
    /// controls with refs a drive plan can aim at (Chrome sends its own page context instead).
    static func context(controls: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm zzz"
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        let line = "\(app). Local time: \(formatter.string(from: Date())) (\(TimeZone.current.identifier))."
        guard controls, let snapshot = AXSnapshotter.shared.capture(budget: 0.2) else { return line }
        return line + "\n" + snapshot.render(limit: 40)
    }

    private func globalPoint(x: Int, y: Int, screen: Int?, in shots: [ScreenShot]) -> CGPoint? {
        PresentPointMapping.screenPoint(x: x, y: y, screen: screen, in: shots)
    }

    /// Speaks and captions a short message of ZEUS's own (errors, "Approved.").
    func say(_ text: String) {
        VoiceLog.logContent("spoken", text)
        if SettingsStore.shared.bool("voice.speakReplies") {
            SystemAudioDucker.begin()
            speaker.speak(text)
            Task { @MainActor [weak self] in
                guard let self else { return }
                while self.speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(80)) }
                SystemAudioDucker.end()
            }
        }
        buddy.showCaption(text)
        buddy.hideCaption()
    }

    /// The last ~240 characters of the reply, cut at a word boundary.
    static func captionTail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 240 else { return trimmed }
        let tail = trimmed.suffix(240)
        return "…" + (tail.drop { !$0.isWhitespace }).trimmingCharacters(in: .whitespaces)
    }

    /// The recogniser sometimes re-hears "Zeus" in its final pass as "Siri", "Zoos" or "Juice",
    /// leaving it at the front of the request ("Siri open calculator"). Drop leading echoes of the
    /// wake phrase so the fast path sees "open calculator".
    nonisolated static func dropWakeEchoes(_ request: String) -> String {
        let echoes: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "zoos", "seuss", "zues", "zus", "juice", "siri", "sirius", "sues"]
        var words = request.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let first = words.first,
              echoes.contains(first.lowercased().trimmingCharacters(in: .punctuationCharacters)), words.count > 1 {
            words.removeFirst()
        }
        // The recogniser's final pass can repeat a word where partial and final overlap
        // ("open open calculator"): collapse immediate repeats.
        var collapsed: [String] = []
        for word in words where collapsed.last?.lowercased() != word.lowercased() { collapsed.append(word) }
        return collapsed.joined(separator: " ")
    }

    private struct OpenedBrain {
        var engine: () -> String
        var events: AsyncThrowingStream<BrainEvent, Error>
    }

    /// Races the front two brains at once. Later brains in the slice start 1.5 s apart.
    private static func openBrains(_ slice: [(id: String, provider: BrainProvider)], request: BrainRequest) -> OpenedBrain {
        guard slice.count >= 2 else {
            let only = slice[0]
            return OpenedBrain(engine: { only.id }, events: only.provider.send(request))
        }
        let turns = slice.map { _ in UUID() }
        let lazy = LazyRacers()
        let lead = 2
        // Only the front two requests are created now. Each later engine's request is created
        // after its stagger delay, and only if the race is still undecided, so a slow first
        // token never sends the prompt to every provider in the slice.
        let racers: [(id: String, events: AsyncThrowingStream<BrainEvent, Error>)] = slice.enumerated().map { index, item in
            let turn = turns[index]
            let provider = item.provider
            let turned = request.with(turn: turn)
            if index < lead { return (item.id, provider.send(turned)) }
            let wait = BrainRace.staggerMs * (index - lead + 1)
            return (item.id, lazy.stream(id: item.id, waitMs: wait) { provider.send(turned) })
        }
        let race = BrainRace.compete(racers) { id in
            lazy.stop(id)
            guard let index = slice.firstIndex(where: { $0.id == id }) else { return }
            let provider = slice[index].provider
            let turn = turns[index]
            Task { await provider.cancel(turn: turn) }
        }
        lazy.setWinner(race.winner)
        return OpenedBrain(engine: { race.winner.winnerID ?? slice[0].id }, events: race.events)
    }

    /// Delayed race entries whose provider request is created only when their turn comes.
    private final class LazyRacers: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = Set<String>()
        private var tasks: [String: Task<Void, Never>] = [:]
        private var winner: BrainRace.Winner?

        func setWinner(_ value: BrainRace.Winner) { lock.withLock { winner = value } }

        func stop(_ id: String) {
            let task: Task<Void, Never>? = lock.withLock {
                stopped.insert(id)
                return tasks.removeValue(forKey: id)
            }
            task?.cancel()
        }

        private func shouldSkip(_ id: String) -> Bool {
            lock.withLock {
                if stopped.contains(id) { return true }
                if let decided = winner?.winnerID, decided != id { return true }
                return false
            }
        }

        func stream(id: String, waitMs: Int,
                    make: @escaping @Sendable () -> AsyncThrowingStream<BrainEvent, Error>) -> AsyncThrowingStream<BrainEvent, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    try? await Task.sleep(for: .milliseconds(waitMs))
                    if Task.isCancelled || self.shouldSkip(id) { continuation.finish(); return }
                    do {
                        for try await event in make() {
                            if Task.isCancelled { break }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                self.lock.withLock { self.tasks[id] = task }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    private static func consume(_ events: AsyncThrowingStream<BrainEvent, Error>, engine: @escaping () -> String,
                                started: Date, onDelta: (String) -> Void) async throws {
        var logged = false
        for try await event in events {
            if Task.isCancelled { throw CancellationError() }
            if case .textDelta(let delta) = event {
                if !logged {
                    logged = true
                    let ms = max(0, Int(Date().timeIntervalSince(started) * 1000))
                    VoiceLog.log("brain", "engine=\(engine()) first_token_ms=\(ms)")
                    BrainLatencyBook.shared.record(engine(), firstTokenMs: Double(ms))
                }
                onDelta(delta)
            }
        }
        let done = max(0, Int(Date().timeIntervalSince(started) * 1000))
        VoiceLog.log("brain", "engine=\(engine()) done_ms=\(done)")
    }

    /// One line for when every engine failed: quota if that's what they all said.
    nonisolated static func allEnginesFailed(_ errors: [String]) -> String {
        if !errors.isEmpty, errors.allSatisfy({ RouterSettings.isQuotaError($0) || RouterSettings.isSignInError($0) }) {
            return "usage limit: every AI I can reach is out of quota or signed out"
        }
        return errors.last ?? "no AI answered"
    }

    /// One sentence, at most 10 words (persona rule, item 5, QA7). Never reads the raw error text
    /// aloud -- it stays in voice.log via the caller's own `VoiceLog.log` -- except the
    /// "can't find the claude" case, whose own text is already a short, clear instruction and is
    /// still passed through `AckLines.clamp` as a safety net.
    static func spokenError(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lowered = text.lowercased()
        if RouterSettings.isQuotaError(text) {
            return "Every AI is out of quota; instant commands still work."
        }
        if lowered.contains("login") || lowered.contains("auth") || lowered.contains("401") {
            return "That AI isn't signed in; check Settings."
        }
        if lowered.contains("can't find the claude") { return AckLines.clamp(text) ?? text }
        if lowered.contains("network") || lowered.contains("offline") || lowered.contains("connect") {
            return "I couldn't reach Claude; check your connection."
        }
        return "The AI failed; try again."
    }

    static func avatarState(for kind: ZeusAction.Kind) -> AvatarState {
        switch kind {
        case .browserClick, .browserClickIndex, .browserSelect: .clicking
        case .browserType, .browserTypeIndex: .typing
        case .browserRead, .browserOpen, .panelOpen: .browsing
        case .browserScroll, .browserBack, .browserForward, .browserSwitchTab, .browserCloseTab, .browserExtract: .browsing
        case .delegateChrome, .delegateDust: .agent
        case .macDrive: .clicking
        case .macWalkthrough, .presentCard: .browsing
        case .browserAgent: .agent
        case .terminalAgent, .terminalOpen, .terminalRun: .typing
        case .research: .browsing
        }
    }
}
