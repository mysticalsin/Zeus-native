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
    private let speaker: any LineSpeaking
    private let presenter: any TalkVisualPresenting
    /// Whether the owner turned on drawing marks on the screen while Zeus answers (off by default).
    private let drawConsent: () -> Bool
    /// Whether the brain gets the screenshots (on by default), and whether Screen Recording is granted.
    private let seeScreenConsent: () -> Bool
    private let screenPermission: () -> Bool
    /// The "I can't see your screen" notice, given once per launch.
    private var sightNotice = ScreenSightNotice()
    /// A drawing from this controller's last answer may still be on screen.
    private var drawActive = false
    /// Later explain beats. Cancelled when the next turn clears the drawing.
    private var explainReveal: Task<Void, Never>?
    /// Sentence start times for the explain pen. Nil until that sentence's audio starts.
    private var explainAudioStarts: [TimeInterval?] = [nil, nil, nil]
    private var explainBegan = Date()

    /// What one turn really sent, for the tests: the brain request, the route it asked for, and every capture the
    /// turn kept for POINT tags and the drive and walkthrough actions.
    struct TurnObservation {
        var request: BrainRequest
        var preferAppClaude: Bool
        var shots: [ScreenShot]
    }
    var turnObserver: ((TurnObservation) -> Void)?
    /// Tests only: the engines a turn races, in place of the router's choice.
    /// Whether the launched `claude` keeps screenshots out of the saved session (so it is sent them). Tests set it.
    var supportsNoSessionPersistence: () -> Bool = { ClaudeFlags.supportsSafeMode }
    var engineCandidatesOverride: (() -> [(engine: BrainEngineID, id: String, provider: BrainProvider)])?
    let brain: BrainProvider
    let chrome: ChromeActions

    /// Called when a listening turn stops for any reason, so the talk key's machine and the wake word listener forget it.
    var onListeningEnded: (() -> Void)?
    private var listening = false {
        didSet { if oldValue, !listening { onListeningEnded?() } }
    }
    /// What a press, a release and an end do outside this controller: warm-ups, volume ducking, screen capture,
    /// the microphone start and stop. Tests swap these so no audio, volume, screen or process is touched.
    @MainActor struct Seams {
        /// The key-press warm-ups (brain, voice, local-model probe) stay written in `press()`; tests turn them off.
        var warmsOnPress = true
        var duckBegin: @MainActor () -> Void = { SystemAudioDucker.begin() }
        var duckEnd: @MainActor () -> Void = { SystemAudioDucker.end() }
        var captureScreens: @MainActor () async -> [ScreenShot] = { await ScreenCapture.captureAll() }
        var speechStart: @MainActor (SpeechInput) throws -> Int = { try $0.start() }
        var speechStop: @MainActor (SpeechInput) async -> String = { await $0.stop() }
        static func silent() -> Seams { Seams(warmsOnPress: false, duckBegin: {}, duckEnd: {}, captureScreens: { [] }) }
    }
    var seams = Seams()
    /// The speech session of the turn that is listening, so a late capture failure never ends a newer turn.
    private var talkSession: Int?
    /// Card on screen when this listen started. A spoken yes uses this id, not whichever card is up at the transcript.
    private var spokenApprovalCardID: String?
    /// Capture failures as the audio thread reports them, readable before their main-actor hop runs.
    private let captureFailures = CaptureFailureLatch()
    private var screenshotsTask: Task<[ScreenShot], Never>?
    private var tabTask: Task<TabContext?, Never>?
    private var turnTask: Task<TurnResult, Never>?
    private var currentTurn: UUID?
    /// The spoken answer in flight: fast tiers racing and the deep follow-up behind them.
    private var fastRace: FastRaceRun?
    /// When the talk key was released, for the per-stage timing log.
    private var turnReleasedAt: ContinuousClock.Instant?
    /// When the last fast answer finished: the deep follow-up is spoken only inside the conversation window.
    private var lastAnswerAt: Date?
    private var history: [Exchange] = []
    /// True from release (or a wake phrase) until the turn's work is done.
    var turnRunning: Bool { turnRun.isActive }
    /// One slot for the turn in flight: a turn cancelled by a new press finishes later and must not clear the newer turn's flag.
    private var turnRun = LatestRun()
    /// When the recogniser last changed its live transcript (hands-free turns end on silence).
    private var lastPartialAt: ContinuousClock.Instant?
    /// The speech-trace generation opened by the current press. A late deliver from an older turn ignores it.
    private var speechGeneration = 0
    private var liveWords = LiveWordsHUD()
    private var heardSomething = false
    private var handsFreeTask: Task<Void, Never>?
    /// Hands-free follow-ups after the wake word (O20): end after 90 s of silence, Esc, or ✕.
    private var wakeConversationActive = false
    /// The Murmure engine for this turn when "Use for voice commands too" is on; nil is Apple live.
    private var turnEngine: (any TranscriptionEngine)?
    /// Starts a brain during a 0.7 s pause. A changed phrase drops it.
    private let ahead = AheadRunner()

    init(buddy: BuddyController, notch: NotchController, brain: BrainProvider,
         speaker: (any LineSpeaking)? = nil, presenter: (any TalkVisualPresenting)? = nil,
         drawConsent: @escaping () -> Bool = { FeatureSettings.talkDrawOnScreen() },
         seeScreen: @escaping () -> Bool = { FeatureSettings.talkSeeScreen() },
         screenPermission: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        _ = Microphones.cache // starts the device watch and the first list read off main, before any press
        self.drawConsent = drawConsent
        seeScreenConsent = seeScreen
        self.screenPermission = screenPermission
        self.buddy = buddy
        self.notch = notch
        self.brain = brain
        chrome = ChromeActions(notch: notch)
        speech = SpeechInput()
        speech.sttPathName = STTFlushLines.talkHold
        self.speaker = speaker ?? Speaker(languageCode: speech.localeIdentifier)
        self.presenter = presenter ?? TalkVisualPresenter()
        speech.onLevel = { [weak buddy] level in
            Task { @MainActor in buddy?.model.audioLevel = level }
        }
        // Live partials warm the fast path up (rules) and time
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
                // A matching command is armed here and runs only if these words are still the final ones.
                FastPath.shared.partial(text)
                self.armAhead(text)
            }
        }
        FastActions.shared.onLateProblem = { [weak self] text in
            guard let self else { return }
            if let visual = ActionMissDraw.from(line: text) {
                self.showActionMiss(visual, speak: true)
                self.say(text)
                self.buddy.showCaption(visual.boltCaption(at: 0))
            } else {
                self.say(text)
            }
        }
        // Perf rule: nothing warms at launch. The talk key going down warms the brain connection, the lean
        // `claude` process and the voice (`KeyDownWarmer`, `Speaker.prewarm`) while Tony is still speaking.
        BrainWarmScheduler.shared.start()
    }

    /// After the words sit still for 0.7 s, start the fastest brain. Commands stay on the instant path.
    private func armAhead(_ text: String) {
        ahead.partial(text) { [weak self] utterance, _ in
            guard let self, AheadBrain.canStart(utterance) else { return }
            // Same privacy rule and provider choice as the real turn, applied before any provider exists.
            // The speculative run is a fast-tier engine launched lean, never a full CLI setup.
            let task = RouterTask.classify(utterance)
            let ordered = BrainLatencyBook.shared.ordered(
                RouterSettings.shared.brainEngineCandidates(task: task, hasAnthropicKey: AnthropicAPIProvider.hasKey), id: \.id)
            let fast = Set(FastTier.fastRace(order: ordered.map(\.engine), ollamaWarm: RouterSettings.shared.ollamaHTTPReachable))
            guard let first = ordered.first(where: { fast.contains($0.engine) }) else { return }
            let request = BrainRequest(turn: UUID(), transcript: utterance, systemPrompt: ZeusPrompt.system, deep: false,
                                       firstTextBudget: Double(FastTier.firstTextBudgetMs) / 1000)
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

    /// One answered turn driven by a scripted reply, for the tests that watch what the turn asks of the voice and the drawing.
    func runScriptedTurn(transcript: String, screenshots: [ScreenShot], replay: (id: String, events: AsyncThrowingStream<BrainEvent, Error>)? = nil,
                         replaySawScreen: Bool = true) async -> TurnResult {
        await runTurn(transcript: transcript, screenshots: screenshots, activeTab: nil, turn: UUID(), deep: false,
                      speak: true, awaitActions: false, replay: replay, replaySawScreen: replaySawScreen)
    }

    /// Hides the marks of the last answer. A turn that never drew makes no presenter call.
    func clearDrawingForNewTurn() {
        explainReveal?.cancel()
        explainReveal = nil
        explainAudioStarts = [nil, nil, nil]
        guard drawActive else { return }
        drawActive = false
        presenter.clear()
    }

    /// Draws a research answer's sources on the display under the pointer, one site at a time.
    /// The summary is spoken by the caller. The marks still appear when that speech is off.
    func showResearch(_ plan: ResearchSourceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyResearch(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyResearch(plan, at: elapsed, shot: shot)
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyResearch(_ plan: ResearchSourceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a research report Zeus could not save, under the pointer.
    /// The caller passes the spoken line. A saved report is not this card.
    func showReportMiss(_ plan: ReportMissDraw, line: String, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else {
            if speak { say(line) }
            return
        }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyReportMiss(plan, at: 0, shot: shot)
        if speak { say(line) }
        buddy.showCaption(plan.boltCaption(at: 0))
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyReportMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyReportMiss(_ plan: ReportMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a saved research report, under the pointer.
    /// The caller passes the spoken line. Source sites are not this card.
    func showReportSaved(_ plan: ReportSavedDraw, line: String, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else {
            if speak { say(line) }
            return
        }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyReportSaved(plan, at: 0, shot: shot)
        if speak { say(line) }
        buddy.showCaption(plan.boltCaption(at: 0))
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyReportSaved(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyReportSaved(_ plan: ReportSavedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws Zeus asking what to research, under the pointer.
    /// The caller passes the spoken line. A saved report is not this card.
    func showResearchAsk(_ plan: ResearchAskDraw, line: String, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else {
            if speak { say(line) }
            return
        }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyResearchAsk(plan, at: 0, shot: shot)
        if speak { say(line) }
        buddy.showCaption(plan.boltCaption(at: 0))
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyResearchAsk(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyResearchAsk(_ plan: ResearchAskDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Menu › Stop Speaking (pressing the talk key also interrupts).
    func stopSpeaking() {
        clearDrawingForNewTurn()
        fastRace?.cancel()
        PersistentClaudeSession.shared.abortBusy()
        turnRun.invalidate()
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        ahead.cancel()
        speaker.stop()
        seams.duckEnd()
        wakeConversationActive = false
        buddy.model.captionVisible = false
        buddy.idle()
    }

    /// Talk turns listen on the microphone chosen for talk (Settings > Voice), resolved now: Automatic is no device, This Mac's
    /// microphone is the built-in device, a specific input is itself or Automatic when it is gone. Dictation's choice is separate.
    /// The device list is read only when a device is chosen.
    static func applyChosenMicrophone(to speech: SpeechInput, defaults: UserDefaults = .standard,
                                      devices: () -> [MicrophoneDevice] = { Microphones.cache.devices() },
                                      builtInUID: () -> String? = { Microphones.cache.builtInUID() }) {
        let choice = TalkMicrophoneChoice.load(defaults)
        speech.deviceUID = choice == .automatic ? nil : choice.resolvedUID(devices: devices(), builtInUID: builtInUID())
    }

    @discardableResult
    func press(builtinCue: Bool = true) -> Bool {
        speechGeneration = speech.noteKeyDown(path: .talkHold)
        // A press during a live turn (a hands-free or wake turn) cuts in and restarts the capture.
        clearDrawingForNewTurn()
        ExplanationAudioArbitration.yieldToNewCapture()
        // A new press always interrupts whatever ZEUS was doing.
        if seams.warmsOnPress { BrainWarmScheduler.shared.talkKeyDown() }
        fastRace?.cancel()
        // A hands-free silence timer from an earlier turn must not release the key the owner is holding now.
        handsFreeTask?.cancel()
        handsFreeTask = nil
        turnRun.invalidate()
        // A barge-in stops generation now, then the key-down warm-up gives the next turn a ready process.
        PersistentClaudeSession.shared.abortBusy()
        if seams.warmsOnPress {
            KeyDownWarmer.talkKeyDown()
            // Off the critical path: the local-model check is read from this cache when the answer starts.
            Task { RouterSettings.shared.noteOllamaHTTPReachable(await OllamaHTTPProbe.isReachable()) }
        }
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        ahead.cancel()
        speaker.stop()
        buddy.model.captionVisible = false
        liveWords.clear()

        turnEngine = DictationHub.shared.controller?.voiceEngine
        speech.recordsSamples = turnEngine != nil
        speech.contextualStrings = DictationVocabularyPrompt.terms(DictationHub.shared.controller?.vocabulary ?? Vocabulary())
        Self.applyChosenMicrophone(to: speech)
        captureFailures.reset()
        spokenApprovalCardID = nil
        let failures = captureFailures
        speech.onCaptureFailure = { [weak self] session, origin, failure in
            // Recorded on the calling thread, so a release before the main-actor hop below still sees it.
            failures.record(session: session, failure: failure)
            Task { @MainActor in self?.handleCaptureFailure(session: session, origin: origin, failure: failure) }
        }
        do {
            talkSession = try seams.speechStart(speech)
            spokenApprovalCardID = SpokenApprovalCapture.atSpeechStart(displayedCardID: notch.model.approval?.id)
        } catch {
            // A start throws before it touches a running capture, so a live turn keeps its handler and session.
            if !listening { speech.onCaptureFailure = nil }
            speech.noteDelivered(generation: speechGeneration)
            VoiceLog.logContent("error", error.localizedDescription, prefix: "can't start listening (mic \(VoicePermissions.mic), speech \(VoicePermissions.speech)): ")
            ZeusSound.play(.voiceError)
            if let cue = VoicePermissions.access.deniedCue, let pane = VoicePermissions.access.deniedPane {
                VoicePermissions.notifyDenied(cue, pane)
            } else {
                let notice = "I can't hear you yet. Check that Zeus has microphone and speech recognition access."
                if let visual = HearDraw.from(message: notice) {
                    showHear(visual, speak: true)
                    say(notice)
                    buddy.showCaption(visual.boltCaption(at: 0))
                } else {
                    say(notice)
                }
            }
            return false
        }
        listening = true
        VoiceLog.log("listen", "started (recogniser \(speech.localeIdentifier))")
        if builtinCue { ZeusSound.play(.listenStart) }
        seams.duckBegin()
        lastPartialAt = nil
        heardSomething = false
        FastPath.shared.reset()
        liveWords.clear()
        buddy.model.audioLevel = 0
        buddy.listen()
        // Screens are captured while you talk, so the answer isn't waiting on them.
        screenshotsTask = Task { await seams.captureScreens() }
        // With Chrome in front, the extension reads the page you're looking at.
        let chromeInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
        tabTask = chromeInFront ? Task { await ChromeBridge.activeTab(elements: true) } : nil
        return true
    }

    func release(builtinCue: Bool = true) {
        guard listening else { return }
        // Capture already gave up for this turn: end it as a failure and do not read or send the partial.
        if let session = talkSession, let failure = captureFailures.failure(for: session) {
            handleCaptureFailure(session: session, origin: 0, failure: failure)
            return
        }
        listening = false
        speech.onCaptureFailure = nil
        talkSession = nil
        turnReleasedAt = .now
        VoiceLatency.shared.begin()
        VoiceLog.log("listen", "stopped")
        if builtinCue { ZeusSound.play(.listenStop) }
        seams.duckEnd()
        handsFreeTask?.cancel()
        handsFreeTask = nil
        buddy.think()
        let run = turnRun.begin()
        turnTask = Task {
            let result = await finishTurn()
            let live = turnRun.finish(run)
            if live, wakeConversationActive, result.error == nil, !result.cancelled {
                handsFree()
            }
            return result
        }
    }

    /// The talk keys became another shortcut while held (⌃⌥C opens Chat): stop listening and send nothing.
    func cancelListening() {
        guard endListeningWithoutSending() else { return }
        VoiceLog.log("listen", "cancelled: the talk keys became another shortcut")
    }

    /// The microphone kept changing (AirPods switching) and capture gave up: end the turn, send nothing, say why.
    func handleCaptureFailure(session: Int, origin: UInt64, failure: SpeechInput.CaptureFailure) {
        guard listening, CaptureFailureHint.owns(session: session, active: talkSession) else { return }
        guard endListeningWithoutSending() else { return }
        // A flapping microphone must not reopen another hands-free turn.
        wakeConversationActive = false
        VoiceLog.log("listen", "capture failed (\(failure)): the turn ended without sending")
        ZeusSound.play(.voiceError)
        notch.topBar?.show(.hint(CaptureFailureHint.text(for: failure)))
    }

    /// Test seam: marks a turn as listening on `session` without opening the microphone.
    func beginListeningForTesting(session: Int) {
        listening = true
        talkSession = session
    }

    var isListeningForTesting: Bool { listening }
    var captureHandlerInstalledForTesting: Bool { speech.onCaptureFailure != nil }
    var talkSessionForTesting: Int? { talkSession }
    var wakeConversationActiveForTesting: Bool {
        get { wakeConversationActive }
        set { wakeConversationActive = newValue }
    }
    /// Test seam: the speech input reports a capture failure the way its audio thread does.
    func deliverCaptureFailureForTesting(session: Int, failure: SpeechInput.CaptureFailure) {
        speech.onCaptureFailure?(session, 0, failure)
    }

    @discardableResult
    private func endListeningWithoutSending() -> Bool {
        guard listening else { return false }
        listening = false
        speech.onCaptureFailure = nil
        talkSession = nil
        spokenApprovalCardID = nil
        handsFreeTask?.cancel()
        handsFreeTask = nil
        ahead.cancel()
        speech.cancel()
        screenshotsTask?.cancel()
        screenshotsTask = nil
        tabTask?.cancel()
        tabTask = nil
        turnEngine = nil
        seams.duckEnd()
        liveWords.clear()
        buddy.model.audioLevel = nil
        buddy.model.captionVisible = false
        buddy.idle()
        return true
    }

    /// "Hey Zeus, open Spotify": the request already heard by the wake-word listener runs as a
    /// voice turn at once. "Hey Zeus" alone opens a hands-free turn that ends when you stop talking.
    func wakeTurn(request: String) {
        guard !listening else { return }
        clearDrawingForNewTurn()
        wakeConversationActive = true
        buddy.call()
        let request = Self.dropWakeEchoes(request.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !request.isEmpty else { VoiceLog.log("wake", "no request after the phrase: listening hands-free"); handsFree(); return }
        VoiceLog.logContent("wake", request, prefix: "same-breath request: ")
        // The same interruption a key press makes: the previous answer, its deep follow-up and any speculative run stop.
        fastRace?.cancel()
        ahead.cancel()
        turnTask?.cancel()
        if let turn = currentTurn { Task { await brain.cancel(turn: turn) } }
        speaker.stop()
        buddy.model.captionVisible = false
        let heardAt = ContinuousClock.now
        VoiceLatency.shared.begin(at: heardAt)
        // Only the LLM path uses these; the fast path never waits for them.
        screenshotsTask = Task { await seams.captureScreens() }
        let chromeInFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome"
        tabTask = chromeInFront ? Task { await ChromeBridge.activeTab(elements: true) } : nil
        buddy.think()
        spokenApprovalCardID = SpokenApprovalCapture.atSpeechStart(displayedCardID: notch.model.approval?.id)
        let run = turnRun.begin()
        turnTask = Task {
            let result = await complete(transcript: request, finalAt: heardAt)
            let live = turnRun.finish(run)
            if live, wakeConversationActive, result.error == nil, !result.cancelled {
                handsFree()
            }
            return result
        }
    }

    /// Milliseconds in a `Duration`, for the wake and idle quiet checks.
    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int((parts.seconds * 1_000) + (parts.attoseconds / 1_000_000_000_000_000))
    }

    /// A voice turn without the key: starts listening and stops after quiet once you have spoken.
    func handsFree() {
        guard press() else { return }
        handsFreeTask?.cancel()
        let opened = ContinuousClock.now
        let wakeSilenceMs = Self.milliseconds(.seconds(WakeConversationTiming.silenceAfterSpeech))
        let idleLimit: Duration = wakeConversationActive ? .seconds(WakeConversationTiming.silenceWhenEmpty) : .seconds(4)
        let hardLimit: Duration = wakeConversationActive ? .seconds(WakeConversationTiming.hardLimit) : .seconds(12)
        handsFreeTask = Task { @MainActor [weak self] in
            while let self, self.listening, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let now = ContinuousClock.now
                let quietFor = self.lastPartialAt.map { now - $0 } ?? (now - opened)
                let quietMs = Self.milliseconds(quietFor)
                let stop: Bool
                if self.heardSomething, self.wakeConversationActive {
                    stop = STTQuiet.reached(quietForMs: quietMs, thresholdMs: wakeSilenceMs)
                } else if self.heardSomething {
                    stop = STTHandsFree.quietEnded(quietForMs: quietMs)
                } else {
                    stop = STTQuiet.reached(quietForMs: quietMs, thresholdMs: Self.milliseconds(idleLimit))
                }
                if stop { break }
                if now - opened > hardLimit { break }
            }
            guard let self, !Task.isCancelled, self.listening else { return }
            self.release()
        }
    }

    /// `zeus listen`: a hands-free voice turn of up to `seconds`, as if the talk key were held.
    func listenTurn(seconds: Double) async -> TurnResult {
        guard !listening else { return TurnResult(error: "Zeus is already listening.") }
        guard press() else {
            return TurnResult(error: "Zeus can't hear yet: microphone or speech recognition access is missing.")
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
        let generation = speechGeneration
        var transcript = await seams.speechStop(speech).trimmingCharacters(in: .whitespacesAndNewlines)
        if let engine = turnEngine, let dictation = DictationHub.shared.controller {
            let samples = speech.takeSamples()
            transcript = await dictation.transcribeVoice(samples: samples, live: transcript, with: engine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        turnEngine = nil
        buddy.model.audioLevel = nil
        speech.noteDelivered(generation: generation)
        return await complete(transcript: transcript, finalAt: .now)
    }

    /// A finished transcript: approval answers, walkthrough steering, the fast path, then the LLM.
    private func complete(transcript: String, finalAt: ContinuousClock.Instant) async -> TurnResult {
        guard !Task.isCancelled else {
            spokenApprovalCardID = nil
            return TurnResult(cancelled: true)
        }
        guard !transcript.isEmpty else {
            spokenApprovalCardID = nil
            VoiceLog.log("transcript", "(\(speech.diagnostics.nothingHeardSummary))")
            buddy.idle()
            return .nothingHeard
        }
        VoiceLog.logContent("transcript", transcript)
        if turnReleasedAt == nil { turnReleasedAt = finalAt }
        if !VoiceLatency.shared.isActive { VoiceLatency.shared.begin(at: finalAt) }
        VoiceLatency.shared.mark(.transcriptFinal)

        let options = SettingsStore.shared
        let capturedCardID = spokenApprovalCardID
        spokenApprovalCardID = nil
        if let approval = notch.model.approval, options.bool("voice.answers"),
           let verdict = ApprovalPhrases.verdict(for: transcript, approve: options.words("voice.approveWords"),
                                                 deny: options.words("voice.denyWords"), open: options.words("voice.openWords")) {
            guard SpokenApprovalCapture.applies(capturedCardID: capturedCardID, displayedCardID: approval.id) else {
                buddy.idle()
                return TurnResult(spoken: "")
            }
            approval.resolve(verdict)
            buddy.idle()
            let result = verdict == .allow ? "Approved" : verdict == .ask ? "Over to the app" : "Denied"
            let answer = result == "Approved" ? "Approved." : result == "Denied" ? "Denied." : "Over to the app."
            if let visual = ApprovalDraw.plan(result: result) {
                showApproval(visual, speak: true)
                say(answer)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else {
                say(answer)
            }
            return TurnResult(spoken: answer)
        }

        // Optional. Off leaves "stop" for the browser agent and a walkthrough.
        if NotchStopAll.matchesVoice(transcript, enabled: AgentSettings.shared.voiceStop) {
            let stopped = notch.stopAllSupervised()
            buddy.idle()
            let answer = stopped.isEmpty ? "Nothing is running." : "Stopped."
            let names = stopped.compactMap { id in notch.model.sessions.first { $0.id == id }?.agent }
            let visual = stopped.isEmpty ? StopAllDraw.idle() : StopAllDraw.halted(names: names)
            if let visual {
                showStopAll(visual, speak: true)
                say(answer)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else {
                say(answer)
            }
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
            if let visual = Self.shortcutVisual(transcript: transcript, spoken: spoken) {
                showShortcut(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else {
                say(spoken)
            }
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
        // An explain request is words plus a drawing plan. Drop any speculative model run first.
        if ExplainShowcase.blocksModelRace(transcript) {
            ahead.cancel()
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
        if let plan = LocalAnswerDraw.plan(answer: answer) {
            showLocalAnswer(plan, speak: speak)
            if speak { say(answer) }
            buddy.showCaption(plan.bolt)
        } else if speak {
            say(answer)
        } else {
            buddy.showCaption(answer)
            buddy.hideCaption()
        }
        remember(transcript, answer)
        return TurnResult(spoken: answer)
    }

    private func speakToday(_ plan: TodayBoardDraw, _ spoken: String, transcript: String, speak: Bool) -> TurnResult {
        showTodayBoard(plan, speak: speak)
        if speak { say(spoken) }
        buddy.showCaption(plan.boltCaption(at: 0))
        remember(transcript, spoken)
        return TurnResult(spoken: spoken)
    }

    /// Builds a present card's steps under the pointer while each step is spoken.
    /// A card with no words is not this drawing.
    private func showPresentSteps(_ plan: PresentStepsDraw, spoken: [String], speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else {
            if speak {
                for line in spoken { speaker.speak(Self.voiced(line)) }
            }
            return
        }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPresentSteps(plan, at: 0, shot: shot)
        if speak {
            for line in spoken { speaker.speak(Self.voiced(line)) }
        }
        buddy.showCaption(plan.boltCaption(at: 0))
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPresentSteps(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPresentSteps(_ plan: PresentStepsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Speaks a line the owner asked Zeus to say, and draws the short card.
    /// A blank line stays spoken only.
    func sayAloud(_ text: String) {
        guard let plan = LocalAnswerDraw.plan(answer: text) else {
            say(text)
            return
        }
        showLocalAnswer(plan, speak: true)
        say(text)
        buddy.showCaption(plan.bolt)
    }

    /// The notch Music page, or a spoken "what's playing", says the track and draws it.
    func sayNowPlaying(title: String, artist: String, playing: Bool) {
        presentNowPlaying(title: title, artist: artist, playing: playing, speak: true)
    }

    /// Nothing is on. The screen shows Playing, then Nothing, while Zeus says so.
    func sayNothingPlaying() {
        presentNothingPlaying(speak: true)
    }

    /// The Weather page, or a spoken weather ask, says the forecast and draws it.
    func sayWeather(degrees: Int, phrase: String, place: String) {
        presentWeather(degrees: degrees, phrase: phrase, place: place, speak: true)
    }

    /// No forecast is loaded. The screen shows Weather, then Not ready.
    func sayWeatherNotReady() {
        presentWeatherNotReady(speak: true)
    }

    /// The Home battery card, or a spoken battery ask, says the charge and draws it.
    func sayBattery(level: Int, charging: Bool, pluggedIn: Bool) {
        presentBattery(level: level, charging: charging, pluggedIn: pluggedIn, speak: true)
    }

    /// This Mac has no battery. The screen shows Battery, then None.
    func sayNoBattery() {
        presentNoBattery(speak: true)
    }

    /// The Home calendar card, or a spoken "what's next", says the next event and draws it.
    func sayNextEvent(title: String, when: String, allDay: Bool) {
        presentNextEvent(title: title, when: when, allDay: allDay, speak: true)
    }

    /// Nothing else is left today. The screen shows Next, then None.
    func sayNoNextEvent() {
        presentNoNextEvent(speak: true)
    }

    /// The Home clock, or a spoken "what time is it", says the time and draws it.
    func sayClock(time: String, period: String) {
        presentClock(time: time, period: period, speak: true)
    }

    /// The Home world clock says each city and draws them.
    func sayWorldClock(_ readings: [CityTimeReading]) {
        presentCityTimes(readings, speak: true)
    }

    private func answerCityTime(_ city: String, speak: Bool) -> TurnResult {
        guard let zone = CityTimeAsk.zone(named: city) else {
            presentUnknownCity(speak: speak)
            return TurnResult(spoken: CityTimeAsk.unknown)
        }
        let parts = CityTimeAsk.parts(now: Date(), timeZone: zone)
        let name = CityTimeAsk.placeName(for: zone)
        presentCity(name: name, time: parts.time, period: parts.period, speak: speak)
        return TurnResult(spoken: CityTimeAsk.line(city: name, time: parts.time, period: parts.period) ?? CityTimeAsk.unknown)
    }

    private func presentCity(name: String, time: String, period: String, speak: Bool) {
        let line = CityTimeAsk.line(city: name, time: time, period: period) ?? ""
        guard let plan = CityTimeDraw.plan(city: name, time: time, period: period) else {
            if speak, !line.isEmpty { say(line) }
            return
        }
        buddy.idle()
        showCityTime(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentCityTimes(_ readings: [CityTimeReading], speak: Bool) {
        let line = CityTimeAsk.line(readings: readings) ?? ""
        guard let plan = CityTimeDraw.plan(readings: readings) else {
            if speak, !line.isEmpty { say(line) }
            return
        }
        buddy.idle()
        showCityTime(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentUnknownCity(speak: Bool) {
        let line = CityTimeAsk.unknown
        let plan = CityTimeDraw.unknown()
        buddy.idle()
        showCityTime(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Home countdown, or a spoken "what's the countdown", says the count and draws it.
    func sayCountdown(title: String, days: Int) {
        presentCountdown(title: title, days: days, speak: true)
    }

    /// No countdown date is set. The screen shows Countdown, then None.
    func sayNoCountdown() {
        presentNoCountdown(speak: true)
    }

    private func answerCountdown(speak: Bool) -> TurnResult {
        let title = SettingsStore.shared.string("home.countdown.title")
        guard let target = TodoQuickAdd.day(SettingsStore.shared.string("home.countdown.date")) else {
            presentNoCountdown(speak: speak)
            return TurnResult(spoken: CountdownAsk.none)
        }
        let days = CountdownAsk.days(to: target, now: Date(), calendar: ZeusDates.calendar())
        presentCountdown(title: title, days: days, speak: speak)
        return TurnResult(spoken: CountdownAsk.line(title: title, days: days))
    }

    private func presentCountdown(title: String, days: Int, speak: Bool) {
        let line = CountdownAsk.line(title: title, days: days)
        let plan = CountdownDraw.plan(title: title, days: days)
        buddy.idle()
        showCountdown(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoCountdown(speak: Bool) {
        let line = CountdownAsk.none
        let plan = CountdownDraw.none()
        buddy.idle()
        showCountdown(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The month card, or a spoken "what's the date", says the day and draws it.
    func sayDate(weekday: String, date: String) {
        presentDate(weekday: weekday, date: date, speak: true)
    }

    private func answerDate(speak: Bool) -> TurnResult {
        let parts = DateAsk.parts(now: Date(), timeZone: .current)
        presentDate(weekday: parts.weekday, date: parts.date, speak: speak)
        return TurnResult(spoken: DateAsk.line(weekday: parts.weekday, date: parts.date) ?? "")
    }

    private func presentDate(weekday: String, date: String, speak: Bool) {
        let line = DateAsk.line(weekday: weekday, date: date) ?? ""
        guard let plan = DateDraw.plan(weekday: weekday, date: date) else {
            if speak, !line.isEmpty { say(line) }
            return
        }
        buddy.idle()
        showDate(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Home note, or a spoken "read my note", says the words and draws them.
    func sayNote(_ text: String) {
        presentNote(text, speak: true)
    }

    /// The pinned note is empty. The screen shows Note, then None.
    func sayNoNote() {
        presentNoNote(speak: true)
    }

    /// The pinned note must not be read. The screen shows Note, then Not stored.
    func saySecretNote() {
        presentSecretNote(speak: true)
    }

    private func answerNote(speak: Bool) -> TurnResult {
        let text = notch.topBar?.note ?? ""
        if NoteAsk.refuses(text) {
            presentSecretNote(speak: speak)
            return TurnResult(spoken: NoteAsk.secret)
        }
        guard let line = NoteAsk.line(text) else {
            presentNoNote(speak: speak)
            return TurnResult(spoken: NoteAsk.none)
        }
        presentNote(text, speak: speak)
        return TurnResult(spoken: line)
    }

    private func presentNote(_ text: String, speak: Bool) {
        guard let line = NoteAsk.line(text), let plan = NoteDraw.plan(text: text) else {
            if NoteAsk.refuses(text) {
                presentSecretNote(speak: speak)
            } else {
                presentNoNote(speak: speak)
            }
            return
        }
        buddy.idle()
        showNote(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoNote(speak: Bool) {
        let line = NoteAsk.none
        let plan = NoteDraw.none()
        buddy.idle()
        showNote(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentSecretNote(speak: Bool) {
        let line = NoteAsk.secret
        let plan = NoteDraw.secret()
        buddy.idle()
        showNote(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Home agents card, or a spoken "what are my agents doing", says who is running and draws it.
    func sayAgents() {
        presentAgents(speak: true)
    }

    private func answerAgents(speak: Bool) -> TurnResult {
        presentAgents(speak: speak)
        return TurnResult(spoken: agentStatusLine())
    }

    private func presentAgents(speak: Bool) {
        let sessions = notch.model.sessions
        if sessions.isEmpty {
            presentNoAgents(speak: speak)
            return
        }
        if sessions.count == 1, let session = sessions.first,
           let line = AgentStatusAsk.line(name: session.agent, state: Self.agentState(session.status)),
           let plan = AgentStatusDraw.plan(name: session.agent, state: Self.agentState(session.status)) {
            buddy.idle()
            showAgentStatus(plan, speak: speak)
            if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
            buddy.showCaption(plan.boltCaption(at: 0))
            return
        }
        let working = sessions.filter { $0.status == .working }.count
        guard let line = AgentStatusAsk.line(count: sessions.count, working: working),
              let plan = AgentStatusDraw.plan(count: sessions.count, working: working) else {
            presentNoAgents(speak: speak)
            return
        }
        buddy.idle()
        showAgentStatus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func agentStatusLine() -> String {
        let sessions = notch.model.sessions
        if sessions.isEmpty { return AgentStatusAsk.none }
        if sessions.count == 1, let session = sessions.first,
           let line = AgentStatusAsk.line(name: session.agent, state: Self.agentState(session.status)) {
            return line
        }
        let working = sessions.filter { $0.status == .working }.count
        return AgentStatusAsk.line(count: sessions.count, working: working) ?? AgentStatusAsk.none
    }

    private static func agentState(_ state: AgentRunState) -> String {
        switch state {
        case .working: "Working"
        case .idle: "Idle"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Failed"
        case .stalled: "Stalled"
        }
    }

    private func presentNoAgents(speak: Bool) {
        let line = AgentStatusAsk.none
        let plan = AgentStatusDraw.none()
        buddy.idle()
        showAgentStatus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The focus card, or a spoken "how much time is left", says the remainder and draws it.
    func sayTimeLeft() {
        presentTimeLeft(speak: true)
    }

    private func answerTimeLeft(speak: Bool) -> TurnResult {
        presentTimeLeft(speak: speak)
        return TurnResult(spoken: timeLeftLine())
    }

    private func presentTimeLeft(speak: Bool) {
        guard let clock = notch.topBar?.focus, clock.isRunning || clock.isPaused else {
            presentNoTimeLeft(speak: speak)
            return
        }
        let seconds = max(0, Int(clock.remaining(at: Date()).rounded()))
        let state = Self.timeLeftState(clock)
        guard let line = TimerLeftAsk.line(seconds: seconds, state: state),
              let plan = TimerLeftDraw.plan(seconds: seconds, state: state) else {
            presentNoTimeLeft(speak: speak)
            return
        }
        buddy.idle()
        showTimeLeft(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func timeLeftLine() -> String {
        guard let clock = notch.topBar?.focus, clock.isRunning || clock.isPaused else {
            return NoTimerDraw.line
        }
        let seconds = max(0, Int(clock.remaining(at: Date()).rounded()))
        return TimerLeftAsk.line(seconds: seconds, state: Self.timeLeftState(clock)) ?? NoTimerDraw.line
    }

    private static func timeLeftState(_ clock: FocusTimer) -> String {
        if clock.isPaused { return "Paused" }
        if clock.phase == .rest { return "Break" }
        if clock.isPlainTimer { return "Running" }
        return "Focus"
    }

    private func presentNoTimeLeft(speak: Bool) {
        let line = NoTimerDraw.line
        guard let plan = NoTimerDraw.from(line: line) else {
            if speak { say(line) }
            return
        }
        buddy.idle()
        showNoTimer(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Reminders page, or a spoken "what's my next reminder", says it and draws it.
    func sayNextReminder(title: String, when: String) {
        presentNextReminder(title: title, when: when, speak: true)
    }

    /// No reminder is left. The screen shows Due, then None.
    func sayNoNextReminder() {
        presentNoNextReminder(speak: true)
    }

    /// Reminders access is missing. The screen shows Due, then Access.
    func sayNextReminderAccess() {
        presentNextReminderAccess(speak: true)
    }

    private func answerNextReminder(speak: Bool) -> TurnResult {
        let reminders = RemindersController.shared
        if !reminders.allowed && reminders.items.isEmpty {
            presentNextReminderAccess(speak: speak)
            return TurnResult(spoken: NextReminderAsk.access)
        }
        guard let item = reminders.items.first(where: { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            presentNoNextReminder(speak: speak)
            return TurnResult(spoken: NextReminderAsk.none)
        }
        let when = item.due.map { ReminderAsk.whenLine($0, hasTime: item.hasTime) } ?? ""
        presentNextReminder(title: item.title, when: when, speak: speak)
        return TurnResult(spoken: NextReminderAsk.line(title: item.title, when: when) ?? NextReminderAsk.none)
    }

    private func presentNextReminder(title: String, when: String, speak: Bool) {
        guard let line = NextReminderAsk.line(title: title, when: when),
              let plan = NextReminderDraw.plan(title: title, when: when) else {
            presentNoNextReminder(speak: speak)
            return
        }
        buddy.idle()
        showNextReminder(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoNextReminder(speak: Bool) {
        let line = NextReminderAsk.none
        let plan = NextReminderDraw.none()
        buddy.idle()
        showNextReminder(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNextReminderAccess(speak: Bool) {
        let line = NextReminderAsk.access
        let plan = NextReminderDraw.access()
        buddy.idle()
        showNextReminder(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Alerts page, or a spoken "how many notifications", says the count and draws it.
    /// The title and the body are not spoken.
    func sayAlerts() {
        presentAlerts(speak: true)
    }

    private func answerAlerts(speak: Bool) -> TurnResult {
        presentAlerts(speak: speak)
        return TurnResult(spoken: alertStatusLine())
    }

    private func presentAlerts(speak: Bool) {
        let alerts = NotificationsController.shared
        if !alerts.enabled {
            presentAlertState(.off, speak: speak)
            return
        }
        if alerts.failure == .noAccess, alerts.visibleItems.isEmpty {
            presentAlertState(.access, speak: speak)
            return
        }
        if alerts.failure != nil, alerts.visibleItems.isEmpty {
            presentAlertState(.failed, speak: speak)
            return
        }
        let visible = alerts.visibleItems
        guard let line = AlertStatusAsk.line(count: visible.count, app: visible.first?.app ?? ""),
              let plan = AlertStatusDraw.plan(count: visible.count, app: visible.first?.app ?? "") else {
            presentAlertState(.none, speak: speak)
            return
        }
        buddy.idle()
        showAlertStatus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func alertStatusLine() -> String {
        let alerts = NotificationsController.shared
        if !alerts.enabled { return AlertStatusAsk.off }
        if alerts.failure == .noAccess, alerts.visibleItems.isEmpty { return AlertStatusAsk.access }
        if alerts.failure != nil, alerts.visibleItems.isEmpty { return AlertStatusAsk.failed }
        let visible = alerts.visibleItems
        return AlertStatusAsk.line(count: visible.count, app: visible.first?.app ?? "") ?? AlertStatusAsk.none
    }

    private enum AlertCard { case off, access, failed, none }

    private func presentAlertState(_ card: AlertCard, speak: Bool) {
        let line: String
        let plan: AlertStatusDraw
        switch card {
        case .off: line = AlertStatusAsk.off; plan = AlertStatusDraw.off()
        case .access: line = AlertStatusAsk.access; plan = AlertStatusDraw.access()
        case .failed: line = AlertStatusAsk.failed; plan = AlertStatusDraw.failed()
        case .none: line = AlertStatusAsk.none; plan = AlertStatusDraw.none()
        }
        buddy.idle()
        showAlertStatus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The To-do page, or a spoken "how many to-dos", says the open count and draws it.
    func sayTodoCount() {
        presentTodoCount(speak: true)
    }

    private func answerTodoCount(speak: Bool) -> TurnResult {
        presentTodoCount(speak: speak)
        return TurnResult(spoken: todoCountLine())
    }

    private func presentTodoCount(speak: Bool) {
        let todo = TodoController.shared
        let open = todo.open.count
        if todo.items.isEmpty {
            presentTodoCountState(.none, speak: speak)
            return
        }
        if open == 0 {
            presentTodoCountState(.clear, speak: speak)
            return
        }
        let overdue = min(todo.overdueCount, open)
        guard let line = TodoCountAsk.line(open: open, overdue: overdue),
              let plan = TodoCountDraw.plan(open: open, overdue: overdue) else {
            presentTodoCountState(.none, speak: speak)
            return
        }
        buddy.idle()
        showTodoCount(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func todoCountLine() -> String {
        let todo = TodoController.shared
        if todo.items.isEmpty { return TodoCountAsk.none }
        let open = todo.open.count
        if open == 0 { return TodoCountAsk.done }
        return TodoCountAsk.line(open: open, overdue: min(todo.overdueCount, open)) ?? TodoCountAsk.none
    }

    private enum TodoCountCard { case none, clear }

    private func presentTodoCountState(_ card: TodoCountCard, speak: Bool) {
        let line = card == .none ? TodoCountAsk.none : TodoCountAsk.done
        let plan = card == .none ? TodoCountDraw.none() : TodoCountDraw.clear()
        buddy.idle()
        showTodoCount(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func answerClock(speak: Bool) -> TurnResult {
        let parts = ClockAsk.parts(now: Date(), timeZone: .current)
        presentClock(time: parts.time, period: parts.period, speak: speak)
        return TurnResult(spoken: ClockAsk.line(time: parts.time, period: parts.period) ?? "")
    }

    private func presentClock(time: String, period: String, speak: Bool) {
        let line = ClockAsk.line(time: time, period: period) ?? ""
        guard let plan = ClockDraw.plan(time: time, period: period) else {
            if speak, !line.isEmpty { say(line) }
            return
        }
        buddy.idle()
        showClock(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func answerNextEvent(speak: Bool) -> TurnResult {
        guard let event = notch.topBar?.nextEvent() else {
            presentNoNextEvent(speak: speak)
            return TurnResult(spoken: NextEventAsk.none)
        }
        let when = NextEventAsk.whenLine(event.start, allDay: event.isAllDay)
        presentNextEvent(title: event.title, when: when, allDay: event.isAllDay, speak: speak)
        return TurnResult(spoken: NextEventAsk.line(title: event.title, when: when, allDay: event.isAllDay) ?? NextEventAsk.none)
    }

    private func presentNextEvent(title: String, when: String, allDay: Bool, speak: Bool) {
        guard let line = NextEventAsk.line(title: title, when: when, allDay: allDay),
              let plan = NextEventDraw.plan(title: title, when: when) else {
            presentNoNextEvent(speak: speak)
            return
        }
        buddy.idle()
        showNextEvent(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoNextEvent(speak: Bool) {
        let line = NextEventAsk.none
        let plan = NextEventDraw.none()
        buddy.idle()
        showNextEvent(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Joining a meeting says the title and draws it.
    func sayMeeting(title: String, place: String) {
        presentMeeting(title: title, place: place, speak: true)
    }

    /// No meeting is left to join. The screen shows Meeting, then None.
    func sayNoMeeting() {
        presentNoMeeting(speak: true)
    }

    private func joinSpokenMeeting(speak: Bool) -> TurnResult {
        guard let event = notch.topBar?.nextMeeting(), event.meetingURL != nil else {
            presentNoMeeting(speak: speak)
            return TurnResult(spoken: MeetingAsk.none)
        }
        let place = MeetingAsk.place(of: event.meetingURL!)
        notch.topBar?.join(event, announce: speak)
        if !speak { presentMeeting(title: event.title, place: place, speak: false) }
        return TurnResult(spoken: MeetingAsk.line(title: event.title, place: place) ?? MeetingAsk.none)
    }

    private func presentMeeting(title: String, place: String, speak: Bool) {
        guard let line = MeetingAsk.line(title: title, place: place),
              let plan = MeetingDraw.plan(title: title, place: place) else {
            presentNoMeeting(speak: speak)
            return
        }
        buddy.idle()
        showMeeting(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoMeeting(speak: Bool) {
        let line = MeetingAsk.none
        let plan = MeetingDraw.none()
        buddy.idle()
        showMeeting(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Reminders field, or a spoken new reminder, says the title and draws it.
    func sayReminder(_ result: RemindersController.AddResult) {
        presentReminder(result, speak: true)
    }

    private func addSpokenReminder(_ text: String, speak: Bool) -> TurnResult {
        let result = RemindersController.shared.add(text)
        presentReminder(result, speak: speak)
        return TurnResult(spoken: Self.reminderLine(result))
    }

    private static func reminderLine(_ result: RemindersController.AddResult) -> String {
        switch result {
        case .added(let title, let when): return ReminderAsk.added(title: title, when: when) ?? ReminderAsk.notSaved
        case .access: return ReminderAsk.access
        case .notSaved: return ReminderAsk.notSaved
        }
    }

    private func presentReminder(_ result: RemindersController.AddResult, speak: Bool) {
        let line = Self.reminderLine(result)
        let plan: ReminderDraw?
        switch result {
        case .added(let title, let when): plan = ReminderDraw.plan(title: title, when: when)
        case .access: plan = ReminderDraw.access()
        case .notSaved: plan = ReminderDraw.notSaved()
        }
        buddy.idle()
        guard let plan else {
            if speak { say(line) }
            return
        }
        showReminder(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func answerBattery(speak: Bool) -> TurnResult {
        guard let battery = notch.topBar?.battery else {
            presentNoBattery(speak: speak)
            return TurnResult(spoken: BatteryAsk.none)
        }
        presentBattery(level: battery.level, charging: battery.charging, pluggedIn: battery.pluggedIn, speak: speak)
        let state = BatteryAsk.state(level: battery.level, charging: battery.charging, pluggedIn: battery.pluggedIn)
        return TurnResult(spoken: BatteryAsk.line(level: battery.level, state: state))
    }

    private func presentBattery(level: Int, charging: Bool, pluggedIn: Bool, speak: Bool) {
        let state = BatteryAsk.state(level: level, charging: charging, pluggedIn: pluggedIn)
        guard let plan = BatteryDraw.plan(level: level, state: state) else {
            presentNoBattery(speak: speak)
            return
        }
        let line = BatteryAsk.line(level: level, state: state)
        buddy.idle()
        showBattery(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNoBattery(speak: Bool) {
        let line = BatteryAsk.none
        let plan = BatteryDraw.none()
        buddy.idle()
        showBattery(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// A keep-awake session the person started or ended. The notch battery notice stays on the notch.
    func sayKeepAwake(_ speech: KeepAwakeSession.Speech) {
        presentKeepAwake(speech, speak: true)
    }

    private func performKeepAwake(_ command: KeepAwakeAsk.Command, speak: Bool) -> TurnResult {
        let session = KeepAwakeSession.shared
        switch command {
        case .startSaved:
            return beginKeepAwake(minutes: session.homeMinutes, speak: speak)
        case .start(let minutes):
            return beginKeepAwake(minutes: minutes, speak: speak)
        case .stop:
            if session.isActive {
                session.end()
                presentKeepAwake(.stopped, speak: speak)
                return TurnResult(spoken: KeepAwakeAsk.stopped)
            }
            presentKeepAwake(.notOn, speak: speak)
            return TurnResult(spoken: KeepAwakeAsk.notOn)
        }
    }

    private func beginKeepAwake(minutes: Int?, speak: Bool) -> TurnResult {
        KeepAwakeSession.shared.start(minutes: minutes)
        if let minutes {
            let length = max(1, minutes)
            presentKeepAwake(.length(length), speak: speak)
            return TurnResult(spoken: KeepAwakeAsk.lengthLine(minutes: length))
        }
        presentKeepAwake(.openEnded, speak: speak)
        return TurnResult(spoken: KeepAwakeAsk.openEnded)
    }

    private func presentKeepAwake(_ speech: KeepAwakeSession.Speech, speak: Bool) {
        let line: String
        let plan: KeepAwakeDraw?
        switch speech {
        case .length(let minutes):
            line = KeepAwakeAsk.lengthLine(minutes: minutes)
            plan = KeepAwakeDraw.plan(minutes: minutes)
        case .openEnded:
            line = KeepAwakeAsk.openEnded
            plan = KeepAwakeDraw.openEnded()
        case .stopped:
            line = KeepAwakeAsk.stopped
            plan = KeepAwakeDraw.stopped()
        case .done:
            line = KeepAwakeAsk.done
            plan = KeepAwakeDraw.done()
        case .notOn:
            line = KeepAwakeAsk.notOn
            plan = KeepAwakeDraw.stopped()
        }
        buddy.idle()
        guard let plan else {
            if speak { say(line) }
            return
        }
        showKeepAwake(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func answerWeather(speak: Bool) -> TurnResult {
        guard let topBar = notch.topBar, let weather = topBar.weather else {
            presentWeatherNotReady(speak: speak)
            return TurnResult(spoken: WeatherAsk.notReady)
        }
        let celsius = weather.temperature
        let value = topBar.useCelsius ? celsius : celsius * 9 / 5 + 32
        let degrees = Int(value.rounded())
        presentWeather(degrees: degrees, phrase: weather.phrase, place: topBar.weatherPlace, speak: speak)
        let line = WeatherAsk.line(degrees: degrees, phrase: weather.phrase, place: topBar.weatherPlace) ?? WeatherAsk.notReady
        return TurnResult(spoken: line)
    }

    private func presentWeather(degrees: Int, phrase: String, place: String, speak: Bool) {
        guard let line = WeatherAsk.line(degrees: degrees, phrase: phrase, place: place),
              let plan = WeatherDraw.plan(phrase: phrase, temperature: "\(degrees) degrees") else {
            presentWeatherNotReady(speak: speak)
            return
        }
        buddy.idle()
        showWeather(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentWeatherNotReady(speak: Bool) {
        let line = WeatherAsk.notReady
        let plan = WeatherDraw.notReady()
        buddy.idle()
        showWeather(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The notch focus controls, or a spoken focus command, say the session and draw it.
    func sayFocus(_ speech: TopBarModel.FocusSpeech) {
        presentFocus(speech, speak: true)
    }

    private func performFocus(_ command: FocusSessionAsk.Command, speak: Bool) -> TurnResult {
        guard let topBar = notch.topBar else {
            let line = FocusSessionAsk.notRunning
            presentFocus(.notRunning, speak: speak)
            return TurnResult(spoken: line)
        }
        let speech: TopBarModel.FocusSpeech
        switch command {
        case .start(let seconds): speech = topBar.beginFocus(seconds: seconds)
        case .pause: speech = topBar.pauseFocusSession()
        case .resume: speech = topBar.resumeFocusSession()
        case .stop: speech = topBar.endFocusSession()
        }
        presentFocus(speech, speak: speak)
        return TurnResult(spoken: Self.focusLine(speech))
    }

    private static func focusLine(_ speech: TopBarModel.FocusSpeech) -> String {
        switch speech {
        case .length(let seconds, let breakTime): return FocusSessionAsk.lengthLine(seconds: seconds, breakTime: breakTime)
        case .paused: return FocusSessionAsk.paused
        case .stopped(let breakTime): return breakTime ? FocusSessionAsk.breakStopped : FocusSessionAsk.focusStopped
        case .notRunning: return FocusSessionAsk.notRunning
        case .focusDone: return FocusSessionAsk.focusDone
        case .breakOver: return FocusSessionAsk.breakOver
        }
    }

    private func presentFocus(_ speech: TopBarModel.FocusSpeech, speak: Bool) {
        let line = Self.focusLine(speech)
        let plan: FocusSessionDraw?
        switch speech {
        case .length(let seconds, let breakTime): plan = FocusSessionDraw.plan(seconds: seconds, breakTime: breakTime)
        case .paused: plan = FocusSessionDraw.paused()
        case .stopped(let breakTime): plan = FocusSessionDraw.stopped(breakTime: breakTime)
        case .notRunning: plan = FocusSessionDraw.ready()
        case .focusDone: plan = FocusSessionDraw.focusDone()
        case .breakOver: plan = FocusSessionDraw.breakOver()
        }
        buddy.idle()
        guard let plan else {
            if speak { say(line) }
            return
        }
        showFocus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func answerNowPlaying(speak: Bool) -> TurnResult {
        if let item = notch.topBar?.nowPlaying,
           NowPlayingAsk.line(title: item.title, artist: item.artist, playing: item.isPlaying) != nil {
            presentNowPlaying(title: item.title, artist: item.artist, playing: item.isPlaying, speak: speak)
            let line = NowPlayingAsk.line(title: item.title, artist: item.artist, playing: item.isPlaying) ?? ""
            return TurnResult(spoken: line)
        }
        presentNothingPlaying(speak: speak)
        return TurnResult(spoken: NowPlayingAsk.nothing)
    }

    private func presentNowPlaying(title: String, artist: String, playing: Bool, speak: Bool) {
        guard let line = NowPlayingAsk.line(title: title, artist: artist, playing: playing) else {
            presentNothingPlaying(speak: speak)
            return
        }
        buddy.idle()
        guard let plan = NowPlayingDraw.plan(title: title, artist: artist, playing: playing) else {
            if speak { say(line) }
            return
        }
        showNowPlaying(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func presentNothingPlaying(speak: Bool) {
        let line = NowPlayingAsk.nothing
        let plan = NowPlayingDraw.nothing()
        buddy.idle()
        showNowPlaying(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the track that is on: Playing or Paused, then the title, then the artist.
    /// The caller speaks the full line.
    private func showNowPlaying(_ plan: NowPlayingDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNowPlaying(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNowPlaying(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNowPlaying(_ plan: NowPlayingDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a focus session: Focus or Break, then the length, Paused, Stopped, or Done.
    /// The caller speaks the full line.
    private func showFocus(_ plan: FocusSessionDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFocus(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFocus(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFocus(_ plan: FocusSessionDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the forecast: Weather, then the sky, then the degrees. The caller speaks the full line.
    private func showWeather(_ plan: WeatherDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWeather(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWeather(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWeather(_ plan: WeatherDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a keep-awake session: Awake, then the length, On, Off, or Done.
    /// The caller speaks the full line.
    private func showKeepAwake(_ plan: KeepAwakeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyKeepAwake(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyKeepAwake(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyKeepAwake(_ plan: KeepAwakeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the charge: Battery, then the state, then the percent. The caller speaks the full line.
    private func showBattery(_ plan: BatteryDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBattery(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBattery(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBattery(_ plan: BatteryDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a saved reminder: Reminder, then the title, then the due line.
    /// The caller speaks the full line.
    private func showReminder(_ plan: ReminderDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyReminder(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyReminder(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyReminder(_ plan: ReminderDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a meeting join: Meeting, then the title, then the place.
    /// The caller speaks the full line.
    private func showMeeting(_ plan: MeetingDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMeeting(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMeeting(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMeeting(_ plan: MeetingDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the next event: Next, then the title, then the time. The caller speaks the full line.
    private func showNextEvent(_ plan: NextEventDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNextEvent(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNextEvent(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNextEvent(_ plan: NextEventDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the wall clock: Clock, then the digits, then AM or PM. The caller speaks the full line.
    private func showClock(_ plan: ClockDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClock(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClock(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClock(_ plan: ClockDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a city time: the city, then the digits, then AM or PM. Several cities start with World.
    /// The caller speaks the full line.
    private func showCityTime(_ plan: CityTimeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCityTime(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCityTime(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCityTime(_ plan: CityTimeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the Home countdown: Countdown, then the title, then the count. The caller speaks the full line.
    private func showCountdown(_ plan: CountdownDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCountdown(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCountdown(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCountdown(_ plan: CountdownDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the calendar date: Date, then the weekday, then the day. The caller speaks the full line.
    private func showDate(_ plan: DateDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDate(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDate(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDate(_ plan: DateDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the pinned note: Note, then the words. The caller speaks the full line.
    private func showNote(_ plan: NoteDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNote(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNote(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNote(_ plan: NoteDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws who is running: Agents, then the name or the count, then the state.
    /// The caller speaks the full line.
    private func showAgentStatus(_ plan: AgentStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgentStatus(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgentStatus(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgentStatus(_ plan: AgentStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the time still left: Left, then the length, then the state. The caller speaks the full line.
    private func showTimeLeft(_ plan: TimerLeftDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTimeLeft(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTimeLeft(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTimeLeft(_ plan: TimerLeftDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the next reminder: Due, then the title, then the due line. The caller speaks the full line.
    private func showNextReminder(_ plan: NextReminderDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNextReminder(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNextReminder(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNextReminder(_ plan: NextReminderDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the notification count: Alerts, then the count, then the newest app.
    /// The caller speaks the full line. The title and the body stay off the card.
    private func showAlertStatus(_ plan: AlertStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAlertStatus(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAlertStatus(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAlertStatus(_ plan: AlertStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the open to-do count: To-dos, then the count, then Open or the overdue count.
    /// The caller speaks the full line.
    private func showTodoCount(_ plan: TodoCountDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTodoCount(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTodoCount(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTodoCount(_ plan: TodoCountDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A spoken "what's the volume" says the level and draws it. Changing the volume stays silent.
    private func answerVolume(speak: Bool) -> TurnResult {
        presentVolume(speak: speak)
        return TurnResult(spoken: volumeLine())
    }

    private func presentVolume(speak: Bool) {
        guard let device = SystemVolume.defaultOutput(),
              let raw = SystemVolume.volume(device),
              let percent = VolumeLevelAsk.percent(of: Double(raw)) else {
            presentVolumeUnread(speak: speak)
            return
        }
        let muted = SystemVolumeControl.isMuted(device: device) || percent == 0
        guard let line = VolumeLevelAsk.line(percent: percent, muted: muted),
              let plan = VolumeLevelDraw.plan(percent: percent, muted: muted) else {
            presentVolumeUnread(speak: speak)
            return
        }
        buddy.idle()
        showVolumeLevel(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func volumeLine() -> String {
        guard let device = SystemVolume.defaultOutput(),
              let raw = SystemVolume.volume(device),
              let percent = VolumeLevelAsk.percent(of: Double(raw)) else { return VolumeLevelAsk.unread }
        let muted = SystemVolumeControl.isMuted(device: device) || percent == 0
        return VolumeLevelAsk.line(percent: percent, muted: muted) ?? VolumeLevelAsk.unread
    }

    private func presentVolumeUnread(speak: Bool) {
        let line = VolumeLevelAsk.unread
        let plan = VolumeLevelDraw.unread()
        buddy.idle()
        showVolumeLevel(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the volume: Volume, then the percent, then On. Muted is Volume, then Muted.
    /// The caller speaks the full line.
    private func showVolumeLevel(_ plan: VolumeLevelDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVolumeLevel(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVolumeLevel(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVolumeLevel(_ plan: VolumeLevelDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A spoken "how's the brightness" says the level and draws it. The volume stays on its own card.
    private func answerBrightness(speak: Bool) -> TurnResult {
        presentBrightness(speak: speak)
        return TurnResult(spoken: brightnessLine())
    }

    private func presentBrightness(speak: Bool) {
        guard let raw = DisplayBrightness.main(),
              let percent = BrightnessLevelAsk.percent(of: raw),
              let line = BrightnessLevelAsk.line(percent: percent),
              let plan = BrightnessLevelDraw.plan(percent: percent) else {
            presentBrightnessUnread(speak: speak)
            return
        }
        buddy.idle()
        showBrightness(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func brightnessLine() -> String {
        guard let raw = DisplayBrightness.main(),
              let percent = BrightnessLevelAsk.percent(of: raw) else { return BrightnessLevelAsk.unread }
        return BrightnessLevelAsk.line(percent: percent) ?? BrightnessLevelAsk.unread
    }

    private func presentBrightnessUnread(speak: Bool) {
        let line = BrightnessLevelAsk.unread
        let plan = BrightnessLevelDraw.unread()
        buddy.idle()
        showBrightness(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the brightness: Brightness, then the percent, then Dim or Bright.
    /// The caller speaks the full line.
    private func showBrightness(_ plan: BrightnessLevelDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBrightness(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBrightness(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBrightness(_ plan: BrightnessLevelDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The agenda list, or a spoken "what's on my agenda", says what is left and draws it.
    func sayAgenda() {
        presentAgenda(speak: true)
    }

    private func answerAgenda(speak: Bool) -> TurnResult {
        presentAgenda(speak: speak)
        return TurnResult(spoken: agendaLine())
    }

    private func upcomingAgenda(now: Date = Date()) -> [TopBarModel.CalendarItem] {
        (notch.topBar?.events ?? []).filter { $0.end > now && AgendaAsk.cardTitle($0.title, limit: 200) != nil }
            .sorted { $0.start < $1.start }
    }

    private func presentAgenda(speak: Bool) {
        let items = upcomingAgenda()
        if items.isEmpty {
            if notch.topBar?.calendarAccess == .denied {
                presentAgendaState(.access, speak: speak)
            } else {
                presentAgendaState(.clear, speak: speak)
            }
            return
        }
        let first = items[0]
        let when = NextEventAsk.whenLine(first.start, allDay: first.isAllDay)
        guard let line = AgendaAsk.line(count: items.count, title: first.title, when: when, allDay: first.isAllDay),
              let plan = AgendaDraw.plan(count: items.count, title: first.title, when: when, allDay: first.isAllDay) else {
            presentAgendaState(.clear, speak: speak)
            return
        }
        buddy.idle()
        showAgenda(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func agendaLine() -> String {
        let items = upcomingAgenda()
        if items.isEmpty {
            return notch.topBar?.calendarAccess == .denied ? AgendaAsk.access : AgendaAsk.clear
        }
        let first = items[0]
        let when = NextEventAsk.whenLine(first.start, allDay: first.isAllDay)
        return AgendaAsk.line(count: items.count, title: first.title, when: when, allDay: first.isAllDay) ?? AgendaAsk.clear
    }

    private enum AgendaCard { case clear, access }

    private func presentAgendaState(_ card: AgendaCard, speak: Bool) {
        let line = card == .clear ? AgendaAsk.clear : AgendaAsk.access
        let plan = card == .clear ? AgendaDraw.clear() : AgendaDraw.access()
        buddy.idle()
        showAgenda(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the agenda: Agenda, then the title or the count, then the time or the next title.
    /// The caller speaks the full line.
    private func showAgenda(_ plan: AgendaDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgenda(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgenda(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgenda(_ plan: AgendaDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The shelf page, or a spoken "what's on my shelf", says the files and draws them.
    func sayShelf() {
        presentShelf(speak: true)
    }

    private func answerShelf(speak: Bool) -> TurnResult {
        presentShelf(speak: speak)
        return TurnResult(spoken: shelfLine())
    }

    private func newestShelfName() -> (count: Int, name: String) {
        let items = (notch.topBar?.shelf ?? []).sorted { $0.addedAt > $1.addedAt }
        return (items.count, items.first?.name ?? "")
    }

    private func presentShelf(speak: Bool) {
        let facts = newestShelfName()
        guard let line = ShelfAsk.line(count: facts.count, name: facts.name),
              let plan = ShelfDraw.plan(count: facts.count, name: facts.name) else {
            presentShelfEmpty(speak: speak)
            return
        }
        buddy.idle()
        showShelf(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func shelfLine() -> String {
        let facts = newestShelfName()
        return ShelfAsk.line(count: facts.count, name: facts.name) ?? ShelfAsk.empty
    }

    private func presentShelfEmpty(speak: Bool) {
        let line = ShelfAsk.empty
        let plan = ShelfDraw.empty()
        buddy.idle()
        showShelf(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the shelf: Shelf, then the count or the name, then the newest name.
    /// The caller speaks the full line.
    private func showShelf(_ plan: ShelfDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyShelf(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyShelf(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyShelf(_ plan: ShelfDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The weather page, or a spoken "will it rain", says when the rain arrives and draws it.
    func sayRain() {
        presentRain(speak: true)
    }

    private func answerRain(speak: Bool) -> TurnResult {
        presentRain(speak: speak)
        return TurnResult(spoken: rainLine())
    }

    private enum RainCard { case now, none, notReady, soon(Int) }

    private func rainCard(now: Date = Date()) -> RainCard {
        guard let weather = notch.topBar?.weather else { return .notReady }
        switch weather.sky {
        case .rain, .drizzle, .storm: return .now
        default: break
        }
        guard let hour = weather.rainSoon(after: now),
              let minutes = RainAsk.minutes(until: hour.time, now: now) else { return .none }
        return .soon(minutes)
    }

    private func presentRain(speak: Bool) {
        switch rainCard() {
        case .now:
            presentRainState(line: RainAsk.now, plan: RainDraw.now(), speak: speak)
        case .none:
            presentRainState(line: RainAsk.none, plan: RainDraw.none(), speak: speak)
        case .notReady:
            presentRainState(line: RainAsk.notReady, plan: RainDraw.notReady(), speak: speak)
        case .soon(let minutes):
            guard let line = RainAsk.line(minutes: minutes), let plan = RainDraw.plan(minutes: minutes) else {
                presentRainState(line: RainAsk.none, plan: RainDraw.none(), speak: speak)
                return
            }
            presentRainState(line: line, plan: plan, speak: speak)
        }
    }

    private func rainLine() -> String {
        switch rainCard() {
        case .now: return RainAsk.now
        case .none: return RainAsk.none
        case .notReady: return RainAsk.notReady
        case .soon(let minutes): return RainAsk.line(minutes: minutes) ?? RainAsk.none
        }
    }

    private func presentRainState(line: String, plan: RainDraw, speak: Bool) {
        buddy.idle()
        showRain(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the rain: Rain, then the wait, Now, None, or Wait.
    /// The caller speaks the full line.
    private func showRain(_ plan: RainDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRain(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRain(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRain(_ plan: RainDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The week grid, or a spoken "what's my week", says the week and draws the count.
    func sayWeek() {
        presentWeek(speak: true)
    }

    private func answerWeek(speak: Bool) -> TurnResult {
        presentWeek(speak: speak)
        return TurnResult(spoken: weekLine())
    }

    private func weekFacts(now: Date = Date()) -> (week: Int, month: String, count: Int)? {
        let calendar = ZeusDates.calendar()
        guard let parts = WeekAsk.parts(now: now, calendar: calendar) else { return nil }
        let topBar = notch.topBar
        let starts = (topBar?.events ?? []).map(\.start) + (topBar?.calendarEvents ?? []).map(\.start)
        let count = WeekAsk.count(starts: starts, now: now, calendar: calendar)
        return (parts.week, parts.month, count)
    }

    private func presentWeek(speak: Bool) {
        guard let facts = weekFacts() else {
            presentWeekAccess(speak: speak)
            return
        }
        if facts.count == 0, notch.topBar?.calendarAccess == .denied {
            presentWeekAccess(speak: speak)
            return
        }
        guard let line = WeekAsk.line(week: facts.week, month: facts.month, count: facts.count),
              let plan = WeekDraw.plan(week: facts.week, month: facts.month, count: facts.count) else {
            presentWeekAccess(speak: speak)
            return
        }
        buddy.idle()
        showWeek(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func weekLine() -> String {
        guard let facts = weekFacts() else { return WeekAsk.access }
        if facts.count == 0, notch.topBar?.calendarAccess == .denied { return WeekAsk.access }
        return WeekAsk.line(week: facts.week, month: facts.month, count: facts.count) ?? WeekAsk.access
    }

    private func presentWeekAccess(speak: Bool) {
        let line = WeekAsk.access
        let plan = WeekDraw.access()
        buddy.idle()
        showWeek(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the week: Week, then the number, then the count. The caller speaks the full line.
    private func showWeek(_ plan: WeekDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWeek(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWeek(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWeek(_ plan: WeekDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The clipboard page, or a spoken "how many clips", says the count and draws the kind.
    /// The words on the clipboard stay off the card.
    func sayClipboard() {
        presentClipboard(speak: true)
    }

    private func answerClipboard(speak: Bool) -> TurnResult {
        presentClipboard(speak: speak)
        return TurnResult(spoken: clipboardLine())
    }

    private func clipboardFacts() -> (count: Int, kind: String) {
        let entries = notch.topBar?.clipboard.entries ?? []
        let kind: String
        switch entries.first?.kind {
        case .text: kind = "text"
        case .link: kind = "link"
        case .image: kind = "image"
        case .file: kind = "file"
        case nil: kind = ""
        }
        return (entries.count, kind)
    }

    private func presentClipboard(speak: Bool) {
        let facts = clipboardFacts()
        guard let line = ClipboardCountAsk.line(count: facts.count, kind: facts.kind),
              let plan = ClipboardCountDraw.plan(count: facts.count, kind: facts.kind) else {
            presentClipboardEmpty(speak: speak)
            return
        }
        buddy.idle()
        showClipboard(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func clipboardLine() -> String {
        let facts = clipboardFacts()
        return ClipboardCountAsk.line(count: facts.count, kind: facts.kind) ?? ClipboardCountAsk.empty
    }

    private func presentClipboardEmpty(speak: Bool) {
        let line = ClipboardCountAsk.empty
        let plan = ClipboardCountDraw.empty()
        buddy.idle()
        showClipboard(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the clipboard count: Clips, then the count or the kind. The caller speaks the full line.
    private func showClipboard(_ plan: ClipboardCountDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClipboard(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClipboard(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClipboard(_ plan: ClipboardCountDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A spoken "what's in front" says the app name and draws it. The window title stays off the card.
    private func answerFront(speak: Bool) -> TurnResult {
        presentFront(speak: speak)
        return TurnResult(spoken: frontLine())
    }

    /// The front app's name only. The window title is not read.
    private func frontAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    }

    private func presentFront(speak: Bool) {
        let name = frontAppName()
        guard let line = FrontAppAsk.line(name: name), let plan = FrontAppDraw.plan(name: name) else {
            presentFrontUnseen(speak: speak)
            return
        }
        buddy.idle()
        showFront(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func frontLine() -> String {
        FrontAppAsk.line(name: frontAppName()) ?? FrontAppAsk.unseen
    }

    private func presentFrontUnseen(speak: Bool) {
        let line = FrontAppAsk.unseen
        let plan = FrontAppDraw.unseen()
        buddy.idle()
        showFront(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the front app: Front, then the name. The caller speaks the full line.
    private func showFront(_ plan: FrontAppDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFront(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFront(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFront(_ plan: FrontAppDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A spoken Caps Lock ask says On or Off and draws it. The notch cue shows the same flag.
    private func answerCaps(speak: Bool) -> TurnResult {
        presentCaps(speak: speak)
        return TurnResult(spoken: capsLine())
    }

    private func capsLockOn() -> Bool {
        NSEvent.modifierFlags.contains(.capsLock)
    }

    private func presentCaps(speak: Bool) {
        let on = capsLockOn()
        let line = CapsLockAsk.line(on: on)
        let plan = CapsLockDraw.plan(on: on)
        buddy.idle()
        showCaps(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func capsLine() -> String {
        CapsLockAsk.line(on: capsLockOn())
    }

    /// Draws Caps Lock: Caps, then On or Off. The caller speaks the full line.
    private func showCaps(_ plan: CapsLockDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCaps(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCaps(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCaps(_ plan: CapsLockDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Focus page, or a spoken "how many rounds", says how many finished today.
    func sayRounds() {
        presentRounds(speak: true)
    }

    private func answerRounds(speak: Bool) -> TurnResult {
        presentRounds(speak: speak)
        return TurnResult(spoken: roundsLine())
    }

    private func roundsToday() -> Int {
        notch.topBar?.focus.roundsToday() ?? 0
    }

    private func presentRounds(speak: Bool) {
        let count = roundsToday()
        guard let line = FocusRoundsAsk.line(count: count), let plan = FocusRoundsDraw.plan(count: count) else {
            presentRoundsNone(speak: speak)
            return
        }
        buddy.idle()
        showRounds(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func roundsLine() -> String {
        FocusRoundsAsk.line(count: roundsToday()) ?? FocusRoundsAsk.none
    }

    private func presentRoundsNone(speak: Bool) {
        let line = FocusRoundsAsk.none
        let plan = FocusRoundsDraw.none()
        buddy.idle()
        showRounds(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the day's rounds: Rounds, then the count, then Today. The caller speaks the full line.
    private func showRounds(_ plan: FocusRoundsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRounds(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRounds(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRounds(_ plan: FocusRoundsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The dictation page, or a spoken "how many words today", says the count.
    /// The dictated words stay off the card.
    func sayWords() {
        presentWords(speak: true)
    }

    private func answerWords(speak: Bool) -> TurnResult {
        presentWords(speak: speak)
        return TurnResult(spoken: wordsLine())
    }

    /// Words dictated since local midnight. The text of each dictation is not read.
    private func dictatedWordsToday() -> Int {
        let history = notch.topBar?.dictationHistory ?? []
        let start = Calendar.current.startOfDay(for: Date())
        return history.filter { $0.datetime >= start }.reduce(0) { $0 + $1.wordCount }
    }

    private func presentWords(speak: Bool) {
        let count = dictatedWordsToday()
        guard let line = DictationWordsAsk.line(count: count), let plan = DictationWordsDraw.plan(count: count) else {
            presentWordsNone(speak: speak)
            return
        }
        buddy.idle()
        showWords(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func wordsLine() -> String {
        DictationWordsAsk.line(count: dictatedWordsToday()) ?? DictationWordsAsk.none
    }

    private func presentWordsNone(speak: Bool) {
        let line = DictationWordsAsk.none
        let plan = DictationWordsDraw.none()
        buddy.idle()
        showWords(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the day's dictated words: Words, then the count, then Today. The caller speaks the full line.
    private func showWords(_ plan: DictationWordsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWords(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWords(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWords(_ plan: DictationWordsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Scribe or Recordly page, or a spoken "are you recording", says who is capturing.
    /// The words being captured stay off the card.
    func sayRecording() {
        presentRecording(.any, speak: true)
    }

    private func answerRecording(_ who: RecordingAsk.Who, speak: Bool) -> TurnResult {
        presentRecording(who, speak: speak)
        return TurnResult(spoken: recordingLine(who))
    }

    private static func recordingSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        let whole = interval.rounded(.down)
        guard whole < Double(Int.max) else { return 0 }
        return Int(whole)
    }

    private func recordingFacts() -> (scribe: Bool, recordly: Bool, seconds: Int) {
        let scribeOn = ScribeController.shared.isRecording
        let recordlyOn = RecordlyController.shared.isRecording
        let seconds: Int
        if scribeOn {
            seconds = Self.recordingSeconds(ScribeController.shared.elapsed)
        } else if recordlyOn {
            seconds = Self.recordingSeconds(RecordlyController.shared.elapsed)
        } else {
            seconds = 0
        }
        return (scribeOn, recordlyOn, seconds)
    }

    private func presentRecording(_ who: RecordingAsk.Who, speak: Bool) {
        let facts = recordingFacts()
        let line = RecordingAsk.line(who: who, scribe: facts.scribe, recordly: facts.recordly, seconds: facts.seconds)
        let plan = RecordingStatusDraw.plan(who: who, scribe: facts.scribe, recordly: facts.recordly, seconds: facts.seconds)
        buddy.idle()
        showRecording(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func recordingLine(_ who: RecordingAsk.Who) -> String {
        let facts = recordingFacts()
        return RecordingAsk.line(who: who, scribe: facts.scribe, recordly: facts.recordly, seconds: facts.seconds)
    }

    /// Draws the recording: Recording, then who, then the clock when one is running.
    private func showRecording(_ plan: RecordingStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRecording(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRecording(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRecording(_ plan: RecordingStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Appearance page, or a spoken "is dark mode on", says whether the Mac is dark.
    func sayDarkMode() {
        presentDarkMode(speak: true)
    }

    private func answerDarkMode(speak: Bool) -> TurnResult {
        presentDarkMode(speak: speak)
        return TurnResult(spoken: darkModeLine())
    }

    /// Nil when macOS has no light-or-dark match.
    private func macIsDark() -> Bool? {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua { return true }
        if match == .aqua { return false }
        return nil
    }

    private func presentDarkMode(speak: Bool) {
        guard let dark = macIsDark() else {
            presentDarkModeUnread(speak: speak)
            return
        }
        let line = DarkModeAsk.line(dark: dark)
        let plan = DarkModeDraw.plan(dark: dark)
        buddy.idle()
        showDarkMode(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func darkModeLine() -> String {
        guard let dark = macIsDark() else { return DarkModeAsk.unread }
        return DarkModeAsk.line(dark: dark)
    }

    private func presentDarkModeUnread(speak: Bool) {
        let line = DarkModeAsk.unread
        let plan = DarkModeDraw.unread()
        buddy.idle()
        showDarkMode(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws Dark Mode: Mode, then Dark, Light, or Can't. The caller speaks the full line.
    private func showDarkMode(_ plan: DarkModeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDarkMode(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDarkMode(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDarkMode(_ plan: DarkModeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Tiling page, or a spoken "is tiling on", says the same word the page shows.
    func sayTiling() {
        presentTiling(speak: true)
    }

    private func answerTiling(speak: Bool) -> TurnResult {
        presentTiling(speak: speak)
        return TurnResult(spoken: tilingLine())
    }

    private func tilingState() -> TilingStatusAsk.State {
        switch TilingController.shared.phase {
        case .off: .off
        case .running: .on
        case .paused: .paused
        case .needsAccessibility: .access
        case .keyClash: .clash
        case .keysUnavailable: .keys
        }
    }

    private func presentTiling(speak: Bool) {
        let state = tilingState()
        let line = TilingStatusAsk.line(state)
        let plan = TilingStatusDraw.plan(state)
        buddy.idle()
        showTiling(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func tilingLine() -> String {
        TilingStatusAsk.line(tilingState())
    }

    /// Draws tiling: Tiling, then the page's word. The caller speaks the full line.
    private func showTiling(_ plan: TilingStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTiling(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTiling(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTiling(_ plan: TilingStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Recordly page, or a spoken "how many screens", says the count and the display in use.
    func sayScreens() {
        presentScreens(speak: true)
    }

    private func answerScreens(speak: Bool) -> TurnResult {
        presentScreens(speak: speak)
        return TurnResult(spoken: screensLine())
    }

    /// The displays attached now, and the name of the one under the pointer.
    private func screenFacts() -> (count: Int, name: String) {
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        let current = screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? screens.first
        return (screens.count, current?.localizedName ?? "")
    }

    private func presentScreens(speak: Bool) {
        let facts = screenFacts()
        guard let line = ScreenCountAsk.line(count: facts.count, name: facts.name),
              let plan = ScreenCountDraw.plan(count: facts.count, name: facts.name) else {
            presentScreensUnseen(speak: speak)
            return
        }
        buddy.idle()
        showScreens(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func screensLine() -> String {
        let facts = screenFacts()
        return ScreenCountAsk.line(count: facts.count, name: facts.name) ?? ScreenCountAsk.unseen
    }

    private func presentScreensUnseen(speak: Bool) {
        let line = ScreenCountAsk.unseen
        let plan = ScreenCountDraw.unseen()
        buddy.idle()
        showScreens(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the displays: Screens, then the count or the name. The caller speaks the full line.
    private func showScreens(_ plan: ScreenCountDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScreens(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScreens(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScreens(_ plan: ScreenCountDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Music page, or a spoken "are my earbuds connected", says whether the output is Bluetooth.
    func sayEarbuds() {
        presentEarbuds(speak: true)
    }

    private func answerEarbuds(speak: Bool) -> TurnResult {
        presentEarbuds(speak: speak)
        return TurnResult(spoken: earbudsLine())
    }

    /// The sound output now. A missing device is unread. Speakers are disconnected, and their name stays off the card.
    private func earbudFacts() -> (connected: Bool?, name: String) {
        let link = EarbudsOutputWatch.currentLink()
        guard link.seen else { return (nil, "") }
        guard link.connected else { return (false, "") }
        guard !MeetingState.hideDetails else { return (true, "") }
        return (true, EarbudsName.display(link.name, hideDetails: false))
    }

    private func presentEarbuds(speak: Bool) {
        let facts = earbudFacts()
        let line = EarbudsStatusAsk.line(connected: facts.connected, name: facts.name)
        let plan = EarbudsStatusDraw.plan(connected: facts.connected, name: facts.name)
        buddy.idle()
        showEarbuds(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func earbudsLine() -> String {
        let facts = earbudFacts()
        return EarbudsStatusAsk.line(connected: facts.connected, name: facts.name)
    }

    /// Draws the connection: Earbuds, then Connected, Disconnected, or Can't. The caller speaks the full line.
    private func showEarbuds(_ plan: EarbudsStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyEarbuds(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyEarbuds(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyEarbuds(_ plan: EarbudsStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Usage page, or a spoken "how much did I use today", says today's tokens.
    func sayUsage() {
        presentUsage(speak: true)
    }

    private func answerUsage(speak: Bool) -> TurnResult {
        presentUsage(speak: speak)
        return TurnResult(spoken: usageLine())
    }

    /// The Usage tab's providers. An empty list means the logs have not been read yet.
    private func usageFacts() -> [UsageTodayFact] {
        UsageModel.shared.providers.map {
            UsageTodayFact(name: $0.provider.title, today: $0.todayTokens, hasData: $0.hasData)
        }
    }

    private func presentUsage(speak: Bool) {
        let facts = usageFacts()
        let line = UsageTodayAsk.line(facts: facts)
        let plan = UsageTodayDraw.plan(facts: facts)
        buddy.idle()
        showUsage(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func usageLine() -> String {
        UsageTodayAsk.line(facts: usageFacts())
    }

    /// Draws today's usage: Usage, then the busiest agent and the token count. The caller speaks the full line.
    private func showUsage(_ plan: UsageTodayDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyUsage(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyUsage(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyUsage(_ plan: UsageTodayDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The teleprompter, or a spoken "how's the prompter", says the counts or the rolling word.
    func sayScript() {
        let facts = scriptFacts(countsOnly: false)
        presentScript(facts, speak: true)
    }

    private func answerScript(_ transcript: String, speak: Bool) -> TurnResult {
        let facts = scriptFacts(countsOnly: PrompterAsk.wantsCounts(transcript))
        presentScript(facts, speak: speak)
        return TurnResult(spoken: PrompterAsk.line(seen: facts.seen, words: facts.words, cues: facts.cues, live: facts.live))
    }

    /// The script counts, and the status word while the prompter is rolling. The text stays off.
    private func scriptFacts(countsOnly: Bool) -> (seen: Bool, words: Int, cues: Int, live: String?) {
        guard let top = notch.topBar else { return (false, 0, 0, nil) }
        let script = PrompterScript(top.script)
        let live = countsOnly ? nil : scriptLive(top)
        return (true, script.wordCount, script.cues.count, live)
    }

    /// The same word the rolling page shows. Idle stays on the counts.
    private func scriptLive(_ top: TopBarModel) -> String? {
        let roll = top.roll
        switch roll.phase {
        case .idle: return nil
        case .countdown: return "Get ready"
        case .paused: return "Paused"
        case .finished: return "The end"
        case .rolling:
            if top.prompterHovered { return "Holding" }
            if roll.voiceFollow, !roll.isSpeaking() { return "Waiting for you" }
            return "Rolling"
        }
    }

    private func presentScript(_ facts: (seen: Bool, words: Int, cues: Int, live: String?), speak: Bool) {
        let line = PrompterAsk.line(seen: facts.seen, words: facts.words, cues: facts.cues, live: facts.live)
        let plan = PrompterDraw.plan(seen: facts.seen, words: facts.words, cues: facts.cues, live: facts.live)
        buddy.idle()
        showScript(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the prompter: Script, then the counts or the page's word. The caller speaks the full line.
    private func showScript(_ plan: PrompterDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScript(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScript(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScript(_ plan: PrompterDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Insomnia page, or a spoken "how's the lid", says the lid line the page shows.
    func sayLid() {
        presentLid(speak: true)
    }

    private func answerLid(speak: Bool) -> TurnResult {
        presentLid(speak: speak)
        return TurnResult(spoken: lidLine())
    }

    private func presentLid(speak: Bool) {
        let word = InsomniaController.shared.lidText
        let line = LidStatusAsk.line(word: word)
        let plan = LidStatusDraw.plan(word: word)
        buddy.idle()
        showLid(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func lidLine() -> String {
        LidStatusAsk.line(word: InsomniaController.shared.lidText)
    }

    /// Draws the lid: Lid, then the page's word. The caller speaks the full line.
    private func showLid(_ plan: LidStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLid(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLid(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLid(_ plan: LidStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Music page, or a spoken "where is the sound going", names the marked output.
    func sayOutput() {
        presentOutput(speak: true)
    }

    private func answerOutput(speak: Bool) -> TurnResult {
        presentOutput(speak: speak)
        return TurnResult(spoken: outputLine())
    }

    /// The output the menu marks. Blank when none is marked.
    private func outputName() -> String {
        OutputDevices.all().first { $0.isDefault }?.name ?? ""
    }

    private func presentOutput(speak: Bool) {
        let name = outputName()
        let line = OutputAsk.line(name: name)
        let plan = OutputDraw.plan(name: name)
        buddy.idle()
        showOutput(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func outputLine() -> String {
        OutputAsk.line(name: outputName())
    }

    /// Draws the output: Output, then the name. The caller speaks the full line.
    private func showOutput(_ plan: OutputDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyOutput(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyOutput(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyOutput(_ plan: OutputDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The dictation page, or a spoken "is dictation on", says the phase. The heard words stay off.
    func sayDictation() {
        presentDictation(speak: true)
    }

    private func answerDictation(speak: Bool) -> TurnResult {
        presentDictation(speak: speak)
        return TurnResult(spoken: dictationLine())
    }

    /// The phase the dictation page shows. The partial transcript is not included.
    private func dictationFacts() -> (seen: Bool, phase: String, mode: String) {
        guard let top = notch.topBar else { return (false, "", "") }
        switch top.dictationPhase {
        case .idle, .done: return (true, "Ready", "")
        case .listening: return (true, "Listening", top.dictationModeName)
        case .transcribing: return (true, "Transcribing", "")
        case .rewriting: return (true, "Polishing", top.dictationModeName)
        case .failed: return (true, "Failed", "")
        }
    }

    private func presentDictation(speak: Bool) {
        let facts = dictationFacts()
        let line = DictationLiveAsk.line(seen: facts.seen, phase: facts.phase, mode: facts.mode)
        let plan = DictationLiveDraw.plan(seen: facts.seen, phase: facts.phase, mode: facts.mode)
        buddy.idle()
        showDictation(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func dictationLine() -> String {
        let facts = dictationFacts()
        return DictationLiveAsk.line(seen: facts.seen, phase: facts.phase, mode: facts.mode)
    }

    /// Draws dictation: Dictation, then the phase, then the mode when the page shows one.
    private func showDictation(_ plan: DictationLiveDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDictation(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDictation(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDictation(_ plan: DictationLiveDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Polyglot page, or a spoken "is translation on", says the phase and the language.
    func sayPolyglot() {
        presentPolyglot(speak: true)
    }

    private func answerPolyglot(speak: Bool) -> TurnResult {
        presentPolyglot(speak: speak)
        return TurnResult(spoken: polyglotLine())
    }

    /// The word the Polyglot page shows, and the language it translates to. Captions stay off.
    private func polyglotFacts() -> (phase: String, language: String) {
        let polyglot = PolyglotController.shared
        let phase: String
        if polyglot.isStarting { phase = PolyglotStatusAsk.starting }
        else if polyglot.isListening { phase = "Listening" }
        else { phase = "Ready" }
        return (phase, PolyglotLanguage.name(for: polyglot.settings.target))
    }

    private func presentPolyglot(speak: Bool) {
        let facts = polyglotFacts()
        let line = PolyglotStatusAsk.line(seen: true, phase: facts.phase, language: facts.language)
        let plan = PolyglotStatusDraw.plan(seen: true, phase: facts.phase, language: facts.language)
        buddy.idle()
        showPolyglot(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func polyglotLine() -> String {
        let facts = polyglotFacts()
        return PolyglotStatusAsk.line(seen: true, phase: facts.phase, language: facts.language)
    }

    /// Draws Polyglot: Polyglot, then Ready, Listening, or Starting, then the language.
    private func showPolyglot(_ plan: PolyglotStatusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPolyglot(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPolyglot(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPolyglot(_ plan: PolyglotStatusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Chat page, or a spoken "how many chats", says the count. Titles stay off.
    func sayChats() {
        presentChats(countsOnly: false, speak: true)
    }

    private func answerChats(_ transcript: String, speak: Bool) -> TurnResult {
        let countsOnly = ChatCountAsk.wantsCount(transcript)
        presentChats(countsOnly: countsOnly, speak: speak)
        let chat = ChatModel.shared
        return TurnResult(spoken: ChatCountAsk.line(writing: chat.isSending, count: chat.conversations.count, countsOnly: countsOnly))
    }

    private func presentChats(countsOnly: Bool, speak: Bool) {
        let chat = ChatModel.shared
        let writing = chat.isSending
        let count = chat.conversations.count
        let line = ChatCountAsk.line(writing: writing, count: count, countsOnly: countsOnly)
        let plan = ChatCountDraw.plan(writing: writing, count: count, countsOnly: countsOnly)
        buddy.idle()
        showChats(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws the chats: Chats, then the count, None, or Writing. The caller speaks the full line.
    private func showChats(_ plan: ChatCountDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyChats(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyChats(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyChats(_ plan: ChatCountDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Insomnia page, or a spoken "how's the heat", says the heat word the page shows.
    func sayHeat() {
        presentHeat(speak: true)
    }

    private func answerHeat(speak: Bool) -> TurnResult {
        presentHeat(speak: speak)
        return TurnResult(spoken: heatLine())
    }

    private func presentHeat(speak: Bool) {
        let word = InsomniaController.shared.heatText
        let line = HeatAsk.line(word: word)
        let plan = HeatDraw.plan(word: word)
        buddy.idle()
        showHeat(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func heatLine() -> String {
        HeatAsk.line(word: InsomniaController.shared.heatText)
    }

    /// Draws the heat: Heat, then Cool, Warm, Hot, or Too hot. The caller speaks the full line.
    private func showHeat(_ plan: HeatDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHeat(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHeat(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHeat(_ plan: HeatDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Voice settings, or a spoken "is Hey Zeus on", says the pill the card shows.
    func sayHeyZeus() {
        presentHeyZeus(speak: true)
    }

    private func answerHeyZeus(speak: Bool) -> TurnResult {
        presentHeyZeus(speak: speak)
        return TurnResult(spoken: heyZeusLine())
    }

    private func presentHeyZeus(speak: Bool) {
        let word = heyZeusWord()
        let line = HeyZeusAsk.line(word: word)
        let plan = HeyZeusDraw.plan(word: word)
        buddy.idle()
        showHeyZeus(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same short word the Settings pill shows. A pause reason stays off the card.
    private func heyZeusWord() -> String {
        let wake = WakeWordController.shared
        if !wake.enabled { return "Off" }
        if wake.listening { return "Listening" }
        if wake.needsPermissions {
            return VoicePermissions.access == .needsPrompt ? "Not asked yet" : "Denied"
        }
        return "Paused"
    }

    private func heyZeusLine() -> String {
        HeyZeusAsk.line(word: heyZeusWord())
    }

    /// Draws Hey Zeus, then Off, Listening, Not asked yet, Denied, or Paused. The caller speaks the full line.
    private func showHeyZeus(_ plan: HeyZeusDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHeyZeus(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHeyZeus(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHeyZeus(_ plan: HeyZeusDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Privacy card, or a spoken "how's face presence", says the status word the card shows.
    func sayFace() {
        presentFace(speak: true)
    }

    private func answerFace(speak: Bool) -> TurnResult {
        presentFace(speak: speak)
        return TurnResult(spoken: faceLine())
    }

    private func presentFace(speak: Bool) {
        let word = faceWord()
        let line = FaceAsk.line(word: word)
        let plan = FaceDraw.plan(word: word)
        buddy.idle()
        showFace(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same word the status row shows. A face name is not read.
    private func faceWord() -> String {
        let controller = FacePresenceController.shared
        return controller.machine.status(at: controller.environment.uptime()).word
    }

    private func faceLine() -> String {
        FaceAsk.line(word: faceWord())
    }

    /// Draws Face, then the page word. The caller speaks the full line.
    private func showFace(_ plan: FaceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFace(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFace(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFace(_ plan: FaceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Continuity tab, or a spoken "where's my keyboard", says where the input is.
    func sayBeamerPlace() {
        presentBeamerPlace(speak: true)
    }

    private func answerBeamerPlace(speak: Bool) -> TurnResult {
        presentBeamerPlace(speak: speak)
        return TurnResult(spoken: beamerPlaceLine())
    }

    private func presentBeamerPlace(speak: Bool) {
        let place = beamerPlace()
        let line = BeamerPlaceAsk.line(phase: place.phase, name: place.name)
        let plan = BeamerPlaceDraw.plan(phase: place.phase, name: place.name)
        buddy.idle()
        showBeamerPlace(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same place the Continuity headline means. A pause still wins over a crossed link.
    private func beamerPlace() -> (phase: String, name: String) {
        let status = BeamerModel.shared.status
        switch status.availability {
        case .notInstalled: return ("Not installed", "")
        case .notRunning: return ("Not running", "")
        case .needsPermission: return ("Needs access", "")
        case .ready:
            if status.paused == true { return ("Paused", "") }
            switch status.link {
            case .idle: return ("This Mac", "")
            case .driving(let name): return ("Driving", name)
            case .drivenBy(let name): return ("Driven", name)
            }
        }
    }

    private func beamerPlaceLine() -> String {
        let place = beamerPlace()
        return BeamerPlaceAsk.line(phase: place.phase, name: place.name)
    }

    /// Draws Beamer, then where the keyboard is. The caller speaks the full line.
    private func showBeamerPlace(_ plan: BeamerPlaceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBeamerPlace(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBeamerPlace(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBeamerPlace(_ plan: BeamerPlaceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Voice settings, or a spoken "which voice", says the Speaks with choice.
    func sayVoiceChoice() {
        presentVoiceChoice(speak: true)
    }

    private func answerVoiceChoice(speak: Bool) -> TurnResult {
        presentVoiceChoice(speak: speak)
        return TurnResult(spoken: voiceChoiceLine())
    }

    private func presentVoiceChoice(speak: Bool) {
        let word = voiceChoiceWord()
        let line = VoiceChoiceAsk.line(word: word)
        let plan = VoiceChoiceDraw.plan(word: word)
        buddy.idle()
        showVoiceChoice(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same choice the Speaks with menu shows. A key is not read.
    private func voiceChoiceWord() -> String {
        let voice = VoiceSettings.shared
        return voice.engineAuto ? VoiceChoiceAsk.automatic : voice.ttsProvider.title
    }

    private func voiceChoiceLine() -> String {
        VoiceChoiceAsk.line(word: voiceChoiceWord())
    }

    /// Draws Voice, then the menu choice. The caller speaks the full line.
    private func showVoiceChoice(_ plan: VoiceChoiceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVoiceChoice(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVoiceChoice(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVoiceChoice(_ plan: VoiceChoiceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The license row, or a spoken "how's my license", says the title the row shows.
    func sayLicense() {
        presentLicense(speak: true)
    }

    private func answerLicense(speak: Bool) -> TurnResult {
        presentLicense(speak: speak)
        return TurnResult(spoken: licenseLine())
    }

    private func presentLicense(speak: Bool) {
        let word = LicenseManager.shared.statusTitle
        let line = LicenseAsk.line(word: word)
        let plan = LicenseDraw.plan(word: word)
        buddy.idle()
        showLicense(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    private func licenseLine() -> String {
        LicenseAsk.line(word: LicenseManager.shared.statusTitle)
    }

    /// Draws License, then the page title. The caller speaks the full line. The key is not read.
    private func showLicense(_ plan: LicenseDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLicense(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLicense(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLicense(_ plan: LicenseDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Permissions, or a spoken "can you see the screen", says whether screen recording is allowed.
    func sayScreenRecording() {
        presentScreenRecording(speak: true)
    }

    private func answerScreenRecording(speak: Bool) -> TurnResult {
        presentScreenRecording(speak: speak)
        return TurnResult(spoken: screenRecordingLine())
    }

    private func presentScreenRecording(speak: Bool) {
        let word = screenRecordingWord()
        let line = ScreenRecordingAsk.line(word: word)
        let plan = ScreenRecordingDraw.plan(word: word)
        buddy.idle()
        showScreenRecording(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same word the Screen Recording row shows. This does not ask macOS.
    private func screenRecordingWord() -> String {
        switch PermissionsModel.CaptureAccess.live.screen() {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not asked yet"
        }
    }

    private func screenRecordingLine() -> String {
        ScreenRecordingAsk.line(word: screenRecordingWord())
    }

    /// Draws Screen, then Allowed, Denied, or Not asked yet. The caller speaks the full line.
    private func showScreenRecording(_ plan: ScreenRecordingDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScreenRecording(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScreenRecording(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScreenRecording(_ plan: ScreenRecordingDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Privacy, or a spoken "can you drive", says how much Zeus may do on its own. It does not start a drive.
    func sayDriveAutonomy() {
        presentDriveAutonomy(speak: true)
    }

    private func answerDriveAutonomy(speak: Bool) -> TurnResult {
        presentDriveAutonomy(speak: speak)
        return TurnResult(spoken: driveAutonomyLine())
    }

    private func presentDriveAutonomy(speak: Bool) {
        let word = driveAutonomyWord()
        let line = DriveAutonomyAsk.line(word: word)
        let plan = DriveAutonomyDraw.plan(word: word)
        buddy.idle()
        showDriveAutonomy(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Privacy menu shows. An unknown stored value uses the default.
    private func driveAutonomyWord() -> String {
        DriveController.autonomy.title
    }

    private func driveAutonomyLine() -> String {
        DriveAutonomyAsk.line(word: driveAutonomyWord())
    }

    /// Draws Drive, then Always ask, Safe steps alone, or Trusted. The caller speaks the full line.
    private func showDriveAutonomy(_ plan: DriveAutonomyDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDriveAutonomy(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDriveAutonomy(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDriveAutonomy(_ plan: DriveAutonomyDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// General, or a spoken "where's the notch", says which screens show it. It does not move the notch.
    func sayNotchPlace() {
        presentNotchPlace(speak: true)
    }

    private func answerNotchPlace(speak: Bool) -> TurnResult {
        presentNotchPlace(speak: speak)
        return TurnResult(spoken: notchPlaceLine())
    }

    private func presentNotchPlace(speak: Bool) {
        let word = notchPlaceWord()
        let line = NotchPlaceAsk.line(word: word)
        let plan = NotchPlaceDraw.plan(word: word)
        buddy.idle()
        showNotchPlace(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the General menu shows. An unknown stored value uses the built-in display.
    private func notchPlaceWord() -> String {
        NotchDisplayMode(label: SettingsStore.shared.string("notch.displays")).rawValue
    }

    private func notchPlaceLine() -> String {
        NotchPlaceAsk.line(word: notchPlaceWord())
    }

    /// Draws Notch, then Built-in display, Display with the pointer, or All displays. The caller speaks the full line.
    private func showNotchPlace(_ plan: NotchPlaceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotchPlace(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotchPlace(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotchPlace(_ plan: NotchPlaceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Assistant, or a spoken "what's the pointing key", says which keys point. It does not start a turn.
    func sayPointingKeys() {
        presentPointingKeys(speak: true)
    }

    private func answerPointingKeys(speak: Bool) -> TurnResult {
        presentPointingKeys(speak: speak)
        return TurnResult(spoken: pointingKeysLine())
    }

    private func presentPointingKeys(speak: Bool) {
        let word = pointingKeysWord()
        let line = PointingKeysAsk.line(word: word)
        let plan = PointingKeysDraw.plan(word: word)
        buddy.idle()
        showPointingKeys(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Pointing keys menu shows.
    private func pointingKeysWord() -> String {
        PointingSettings.shortcutName
    }

    private func pointingKeysLine() -> String {
        PointingKeysAsk.line(word: pointingKeysWord())
    }

    /// Draws Pointing, then Control-Option, Right Option, or Fn (Globe). The caller speaks the full line.
    private func showPointingKeys(_ plan: PointingKeysDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPointingKeys(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPointingKeys(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPointingKeys(_ plan: PointingKeysDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Shortcuts, or a spoken "what's the chat shortcut", says how the chat window opens. It does not open the window.
    func sayChatShortcut() {
        presentChatShortcut(speak: true)
    }

    private func answerChatShortcut(speak: Bool) -> TurnResult {
        presentChatShortcut(speak: speak)
        return TurnResult(spoken: chatShortcutLine())
    }

    private func presentChatShortcut(speak: Bool) {
        let word = chatShortcutWord()
        let line = ChatShortcutAsk.line(word: word)
        let plan = ChatShortcutDraw.plan(word: word)
        buddy.idle()
        showChatShortcut(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Shortcuts menu shows.
    private func chatShortcutWord() -> String {
        ChatHotkeyMonitor.shared.hotkey.menuTitle
    }

    private func chatShortcutLine() -> String {
        ChatShortcutAsk.line(word: chatShortcutWord())
    }

    /// Draws Chat, then the shortcut. The caller speaks the full line.
    private func showChatShortcut(_ plan: ChatShortcutDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyChatShortcut(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyChatShortcut(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyChatShortcut(_ plan: ChatShortcutDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Assistant, or a spoken "who answers", says the provider. It does not read a key.
    func sayProvider() {
        presentProvider(speak: true)
    }

    private func answerProvider(speak: Bool) -> TurnResult {
        presentProvider(speak: speak)
        return TurnResult(spoken: providerLine())
    }

    private func presentProvider(speak: Bool) {
        let word = providerWord()
        let line = ProviderAsk.line(word: word)
        let plan = ProviderDraw.plan(word: word)
        buddy.idle()
        showProvider(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Provider menu shows. A key stays off the card.
    private func providerWord() -> String {
        SettingsStore.shared.string("assistant.provider")
    }

    private func providerLine() -> String {
        ProviderAsk.line(word: providerWord())
    }

    /// Draws Provider, then Claude CLI, OpenAI, or Anthropic. The caller speaks the full line.
    private func showProvider(_ plan: ProviderDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyProvider(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyProvider(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyProvider(_ plan: ProviderDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Appearance, or a spoken "where's the music from", says which player the notch follows. It does not start playback.
    func sayMusicSource() {
        presentMusicSource(speak: true)
    }

    private func answerMusicSource(speak: Bool) -> TurnResult {
        presentMusicSource(speak: speak)
        return TurnResult(spoken: musicSourceLine())
    }

    private func presentMusicSource(speak: Bool) {
        let word = musicSourceWord()
        let line = MusicSourceAsk.line(word: word)
        let plan = MusicSourceDraw.plan(word: word)
        buddy.idle()
        showMusicSource(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Show music from menu uses. An unknown stored value follows any player.
    private func musicSourceWord() -> String {
        NowPlayingArbiter.Follow(label: SettingsStore.shared.string(NowPlayingHub.followSettingID)).label
    }

    private func musicSourceLine() -> String {
        MusicSourceAsk.line(word: musicSourceWord())
    }

    /// Draws Source, then Any player, Music, or Spotify. The caller speaks the full line.
    private func showMusicSource(_ plan: MusicSourceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMusicSource(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMusicSource(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMusicSource(_ plan: MusicSourceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Appearance, or a spoken "what's the card style", says the selected look. It does not change it.
    func sayCardStyle() {
        presentCardStyle(speak: true)
    }

    private func answerCardStyle(speak: Bool) -> TurnResult {
        presentCardStyle(speak: speak)
        return TurnResult(spoken: cardStyleLine())
    }

    private func presentCardStyle(speak: Bool) {
        let word = cardStyleWord()
        let line = CardStyleAsk.line(word: word)
        let plan = CardStyleDraw.plan(word: word)
        buddy.idle()
        showCardStyle(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the selected picture uses. An unknown stored value is Liquid Glass.
    private func cardStyleWord() -> String {
        CardFinish.resolve(SettingsStore.shared.string("appearance.cardStyle")).rawValue
    }

    private func cardStyleLine() -> String {
        CardStyleAsk.line(word: cardStyleWord())
    }

    /// Draws Look, then the picture title. The caller speaks the full line.
    private func showCardStyle(_ plan: CardStyleDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCardStyle(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCardStyle(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCardStyle(_ plan: CardStyleDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The pointer row, or a spoken "when do you show up", says when Zeus appears. It does not change that.
    func sayPointerBuddy() {
        presentPointerBuddy(speak: true)
    }

    private func answerPointerBuddy(speak: Bool) -> TurnResult {
        presentPointerBuddy(speak: speak)
        return TurnResult(spoken: pointerBuddyLine())
    }

    private func presentPointerBuddy(speak: Bool) {
        let word = pointerBuddyWord()
        let line = PointerBuddyAsk.line(word: word)
        let plan = PointerBuddyDraw.plan(word: word)
        buddy.idle()
        showPointerBuddy(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the pointer menu uses. An unknown stored value is When I call him.
    private func pointerBuddyWord() -> String {
        BuddyPreference.shared.show.title
    }

    private func pointerBuddyLine() -> String {
        PointerBuddyAsk.line(word: pointerBuddyWord())
    }

    /// Draws Pointer, then the menu title. The caller speaks the full line.
    private func showPointerBuddy(_ plan: PointerBuddyDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPointerBuddy(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPointerBuddy(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPointerBuddy(_ plan: PointerBuddyDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Notch behavior, or a spoken "how does the notch open", says Hover or Click. It does not open the notch.
    func sayNotchOpen() {
        presentNotchOpen(speak: true)
    }

    private func answerNotchOpen(speak: Bool) -> TurnResult {
        presentNotchOpen(speak: speak)
        return TurnResult(spoken: notchOpenLine())
    }

    private func presentNotchOpen(speak: Bool) {
        let word = notchOpenWord()
        let line = NotchOpenAsk.line(word: word)
        let plan = NotchOpenDraw.plan(word: word)
        buddy.idle()
        showNotchOpen(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the Open the notch on menu uses. An unknown stored value is Hover.
    private func notchOpenWord() -> String {
        switch NotchOpenTrigger(label: SettingsStore.shared.string("notch.openTrigger")) {
        case .click: return "Click"
        case .hover: return "Hover"
        }
    }

    private func notchOpenLine() -> String {
        NotchOpenAsk.line(word: notchOpenWord())
    }

    /// Draws Open, then Hover or Click. The caller speaks the full line.
    private func showNotchOpen(_ plan: NotchOpenDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotchOpen(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotchOpen(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotchOpen(_ plan: NotchOpenDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The light pictures, or a spoken "what's the halo", say the notch light. They do not change it.
    func sayHaloLight() {
        presentHaloLight(speak: true)
    }

    private func answerHaloLight(speak: Bool) -> TurnResult {
        presentHaloLight(speak: speak)
        return TurnResult(spoken: haloLightLine())
    }

    private func presentHaloLight(speak: Bool) {
        let word = haloLightWord()
        let line = HaloLightAsk.line(word: word)
        let plan = HaloLightDraw.plan(word: word)
        buddy.idle()
        showHaloLight(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same title the selected picture uses. An unknown stored value is Classic halo.
    private func haloLightWord() -> String {
        HaloStyle.resolve(SettingsStore.shared.string("halo.style")).title
    }

    private func haloLightLine() -> String {
        HaloLightAsk.line(word: haloLightWord())
    }

    /// Draws Light, then the picture title. The caller speaks the full line.
    private func showHaloLight(_ plan: HaloLightDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHaloLight(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHaloLight(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHaloLight(_ plan: HaloLightDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Home card, or a spoken "what's on home", says the four widgets. It does not change them.
    func sayHomeCards() {
        presentHomeCards(speak: true)
    }

    private func answerHomeCards(speak: Bool) -> TurnResult {
        presentHomeCards(speak: speak)
        return TurnResult(spoken: homeCardsLine())
    }

    private func presentHomeCards(speak: Bool) {
        let words = homeCardWords()
        let line = HomeCardsAsk.line(words: words)
        let plan = HomeCardsDraw.plan(words: words)
        buddy.idle()
        showHomeCards(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same titles the four Home slots use. An unknown stored value takes that slot's default.
    private func homeCardWords() -> [String] {
        let stored = HomeSlots.settingIDs.map { SettingsStore.shared.string($0) }
        return HomeSlots(stored).kinds.map(\.title)
    }

    private func homeCardsLine() -> String {
        HomeCardsAsk.line(words: homeCardWords())
    }

    /// Draws Home, then each card. The caller speaks the full line.
    private func showHomeCards(_ plan: HomeCardsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHomeCards(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHomeCards(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHomeCards(_ plan: HomeCardsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The level-light rows, or a spoken "which notch lights", say which of the three are on. They do not change them.
    func sayNotchLights() {
        presentNotchLights(speak: true)
    }

    private func answerNotchLights(speak: Bool) -> TurnResult {
        presentNotchLights(speak: speak)
        return TurnResult(spoken: notchLightsLine())
    }

    private func presentNotchLights(speak: Bool) {
        let words = notchLightWords()
        let line = NotchLightsAsk.line(words: words)
        let plan = NotchLightsDraw.plan(words: words)
        buddy.idle()
        showNotchLights(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Volume, then brightness, then the keyboard, for each light that is on. Unset values follow the page default, on.
    private func notchLightWords() -> [String] {
        let pairs = [("lights.hud.volume", "Volume"), ("lights.hud.brightness", "Brightness"), ("lights.hud.keyboard", "Keyboard")]
        return pairs.compactMap { SettingsStore.shared.bool($0.0) ? $0.1 : nil }
    }

    private func notchLightsLine() -> String {
        NotchLightsAsk.line(words: notchLightWords())
    }

    /// Draws Lights, then each light that is on, or None. The caller speaks the full line.
    private func showNotchLights(_ plan: NotchLightsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotchLights(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotchLights(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotchLights(_ plan: NotchLightsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Top bar tabs card, or a spoken "which tabs are on", says the row. It does not switch a tab.
    func sayTopBarTabs() {
        presentTopBarTabs(speak: true)
    }

    private func answerTopBarTabs(speak: Bool) -> TurnResult {
        presentTopBarTabs(speak: speak)
        return TurnResult(spoken: topBarTabsLine())
    }

    private func presentTopBarTabs(speak: Bool) {
        let words = topBarTabWords()
        let line = TopBarTabsAsk.line(words: words)
        let plan = TopBarTabsDraw.plan(words: words)
        buddy.idle()
        showTopBarTabs(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same titles the open notch shows, Home first. Reading them does not switch a tab.
    private func topBarTabWords() -> [String] {
        TopBarLayout.liveTitles()
    }

    private func topBarTabsLine() -> String {
        TopBarTabsAsk.line(words: topBarTabWords())
    }

    /// Draws Tabs, then up to four names. The caller speaks the full line.
    private func showTopBarTabs(_ plan: TopBarTabsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTopBarTabs(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTopBarTabs(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTopBarTabs(_ plan: TopBarTabsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The cue rows, or a spoken "what are the cue sounds", say the four styles. They do not play them.
    func sayCueSounds() {
        presentCueSounds(speak: true)
    }

    private func answerCueSounds(speak: Bool) -> TurnResult {
        presentCueSounds(speak: speak)
        return TurnResult(spoken: cueSoundsLine())
    }

    private func presentCueSounds(speak: Bool) {
        let styles = cueSoundStyles()
        let line = CueSoundsAsk.line(start: styles.start, requests: styles.requests, answer: styles.answer, done: styles.done)
        let plan = CueSoundsDraw.plan(start: styles.start, requests: styles.requests, answer: styles.answer, done: styles.done)
        buddy.idle()
        showCueSounds(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same names the four menus use. An unknown stored value uses that cue's first sound. Off stays Off.
    private func cueSoundStyles() -> (start: String, requests: String, answer: String, done: String) {
        func style(_ id: String, _ slot: SoundSlot) -> String {
            let value = SettingsStore.shared.string(id)
            if value == "Off" || SoundCatalog.styleNames(for: slot).contains(value) { return value }
            return SoundCatalog.styleNames(for: slot).first ?? "Off"
        }
        return (style("sound.startStyle", .runStart), style("sound.approvalStyle", .request), style("sound.answerStyle", .answer), style("sound.doneStyle", .done))
    }

    private func cueSoundsLine() -> String {
        let styles = cueSoundStyles()
        return CueSoundsAsk.line(start: styles.start, requests: styles.requests, answer: styles.answer, done: styles.done)
    }

    /// Draws Sounds, then the four cues. The caller speaks the full line.
    private func showCueSounds(_ plan: CueSoundsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCueSounds(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCueSounds(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCueSounds(_ plan: CueSoundsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The language row, or a spoken "how's dictation set", says the language, the key, and the engine. It does not start dictation.
    func sayDictationSetup() {
        presentDictationSetup(speak: true)
    }

    private func answerDictationSetup(speak: Bool) -> TurnResult {
        presentDictationSetup(speak: speak)
        return TurnResult(spoken: dictationSetupLine())
    }

    private func presentDictationSetup(speak: Bool) {
        let setup = dictationSetupWords()
        let line = DictationSetupAsk.line(language: setup.language, key: setup.key, engine: setup.engine)
        let plan = DictationSetupDraw.plan(language: setup.language, key: setup.key, engine: setup.engine)
        buddy.idle()
        showDictationSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same titles the menus use. An unknown stored value uses Automatic, Hold to speak, and Parakeet v3.
    private func dictationSetupWords() -> (language: String, key: String, engine: String) {
        let settings = DictationSettings.shared
        return (settings.language.title, settings.selectedBehavior.title, settings.engine.title)
    }

    private func dictationSetupLine() -> String {
        let setup = dictationSetupWords()
        return DictationSetupAsk.line(language: setup.language, key: setup.key, engine: setup.engine)
    }

    /// Draws Dictation, then the language, the key, and the engine. The caller speaks the full line.
    private func showDictationSetup(_ plan: DictationSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDictationSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDictationSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDictationSetup(_ plan: DictationSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Voice cues card, or a spoken "which voice cues", says which of the four play. It does not change them.
    func sayVoiceCues() {
        presentVoiceCues(speak: true)
    }

    private func answerVoiceCues(speak: Bool) -> TurnResult {
        presentVoiceCues(speak: speak)
        return TurnResult(spoken: voiceCuesLine())
    }

    private func presentVoiceCues(speak: Bool) {
        let words = voiceCueWords()
        let line = VoiceCuesAsk.line(words: words)
        let plan = VoiceCuesDraw.plan(words: words)
        buddy.idle()
        showVoiceCues(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Listening, stopped, the answer, then an error, for each cue that is on. Unset values follow the page default, on.
    private func voiceCueWords() -> [String] {
        let prefs = ExtraPreferences.shared
        let pairs = [(prefs.soundListenStart, "Listening"), (prefs.soundListenStop, "Stopped"), (prefs.soundVoiceDone, "Answer"), (prefs.soundVoiceError, "Error")]
        return pairs.compactMap { $0.0 ? $0.1 : nil }
    }

    private func voiceCuesLine() -> String {
        VoiceCuesAsk.line(words: voiceCueWords())
    }

    /// Draws Voice, then each cue that plays, or None. The caller speaks the full line.
    private func showVoiceCues(_ plan: VoiceCuesDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVoiceCues(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVoiceCues(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVoiceCues(_ plan: VoiceCuesDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Day to day card, or a spoken "what's on day to day", says which switches are on. It does not change them.
    func sayDayToDay() {
        presentDayToDay(speak: true)
    }

    private func answerDayToDay(speak: Bool) -> TurnResult {
        presentDayToDay(speak: speak)
        return TurnResult(spoken: dayToDayLine())
    }

    private func presentDayToDay(speak: Bool) {
        let words = dayToDayWords()
        let line = DayToDayAsk.line(words: words)
        let plan = DayToDayDraw.plan(words: words)
        buddy.idle()
        showDayToDay(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Login, awake, music, meeting, sharing, then welcome, for each switch that is on.
    /// An unset value follows the catalog default. Reading them does not change login or sleep.
    private func dayToDayWords() -> [String] {
        let store = SettingsStore.shared
        let pairs = [
            ("general.launchAtLogin", "Login"),
            ("general.keepAwake", "Awake"),
            ("keepAwake.whileMusic", "Music"),
            ("general.meetingMode", "Meeting"),
            ("general.showInScreenSharing", "Sharing"),
            ("general.welcomeBack", "Welcome"),
        ]
        return pairs.compactMap { store.bool($0.0) ? $0.1 : nil }
    }

    private func dayToDayLine() -> String {
        DayToDayAsk.line(words: dayToDayWords())
    }

    /// Draws Day, then up to four switches that are on, or None. The caller speaks the full line.
    private func showDayToDay(_ plan: DayToDayDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDayToDay(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDayToDay(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDayToDay(_ plan: DayToDayDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Teleprompter card, or a spoken "how's the prompter set", says which switches are on. It does not change them.
    func sayPrompterSetup() {
        presentPrompterSetup(speak: true)
    }

    private func answerPrompterSetup(speak: Bool) -> TurnResult {
        presentPrompterSetup(speak: speak)
        return TurnResult(spoken: prompterSetupLine())
    }

    private func presentPrompterSetup(speak: Bool) {
        let words = prompterSetupWords()
        let line = PrompterSetupAsk.line(words: words)
        let plan = PrompterSetupDraw.plan(words: words)
        buddy.idle()
        showPrompterSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Follow, slides, private, mirror, then countdown, for each switch that is on.
    /// A missing key follows the page default. Reading them does not open the prompter.
    private func prompterSetupWords() -> [String] {
        let pairs = [
            ("prompter.followPresentation", "Follow", false),
            ("prompter.followAdvances", "Slides", false),
            ("prompterWindow.private", "Private", true),
            ("prompterWindow.mirror", "Mirror", false),
            ("prompterWindow.countdown", "Countdown", true),
        ]
        return pairs.compactMap { prompterSwitch($0.0, default: $0.2) ? $0.1 : nil }
    }

    /// The same read as the Teleprompter switches: a missing key keeps the page default.
    private func prompterSwitch(_ key: String, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func prompterSetupLine() -> String {
        PrompterSetupAsk.line(words: prompterSetupWords())
    }

    /// Draws Prompt, then up to four switches that are on, or None. The caller speaks the full line.
    private func showPrompterSetup(_ plan: PrompterSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPrompterSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPrompterSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPrompterSetup(_ plan: PrompterSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Browser agent card, or a spoken "how's the browser agent set", says the three choices. It does not start a task.
    func sayBrowserAgent() {
        presentBrowserAgent(speak: true)
    }

    private func answerBrowserAgent(speak: Bool) -> TurnResult {
        presentBrowserAgent(speak: speak)
        return TurnResult(spoken: browserAgentLine())
    }

    private func presentBrowserAgent(speak: Bool) {
        let parts = browserAgentParts()
        let line = BrowserAgentAsk.line(work: parts.work, steps: parts.steps, browser: parts.browser)
        let plan = BrowserAgentDraw.plan(work: parts.work, steps: parts.steps, browser: parts.browser)
        buddy.idle()
        showBrowserAgent(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// On or off, the step menu, and the browser menu. An unset value follows the catalog default.
    /// Reading them does not start a web task, and the extra ask-words stay off the card.
    private func browserAgentParts() -> (work: String, steps: String, browser: String) {
        let store = SettingsStore.shared
        let work = store.bool("browserAgent.enabled") ? "On" : "Off"
        return (work, store.string("browserAgent.maxSteps"), store.string("browserAgent.backend"))
    }

    private func browserAgentLine() -> String {
        let parts = browserAgentParts()
        return BrowserAgentAsk.line(work: parts.work, steps: parts.steps, browser: parts.browser)
    }

    /// Draws Browser, then work, steps, and which browser. The caller speaks the full line.
    private func showBrowserAgent(_ plan: BrowserAgentDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBrowserAgent(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBrowserAgent(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBrowserAgent(_ plan: BrowserAgentDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Polyglot card, or a spoken "how's polyglot set", says the three choices. It does not start translation.
    func sayPolyglotSetup() {
        presentPolyglotSetup(speak: true)
    }

    private func answerPolyglotSetup(speak: Bool) -> TurnResult {
        presentPolyglotSetup(speak: speak)
        return TurnResult(spoken: polyglotSetupLine())
    }

    private func presentPolyglotSetup(speak: Bool) {
        let parts = polyglotSetupParts()
        let line = PolyglotSetupAsk.line(work: parts.work, listen: parts.listen, into: parts.into)
        let plan = PolyglotSetupDraw.plan(work: parts.work, listen: parts.listen, into: parts.into)
        buddy.idle()
        showPolyglotSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// On or off, the listen menu, and a Translate to name. An unknown language stays unread.
    /// Reading them does not start Polyglot, and caption text stays off the card.
    private func polyglotSetupParts() -> (work: String, listen: String, into: String) {
        let settings = PolyglotSettings.shared
        let work = settings.enabled ? "On" : "Off"
        let into = PolyglotLanguage.targets.first { $0.code == settings.target }?.name ?? settings.target
        return (work, settings.source.title, into)
    }

    private func polyglotSetupLine() -> String {
        let parts = polyglotSetupParts()
        return PolyglotSetupAsk.line(work: parts.work, listen: parts.listen, into: parts.into)
    }

    /// Draws Translate, then work, where it listens, and the language. The caller speaks the full line.
    private func showPolyglotSetup(_ plan: PolyglotSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPolyglotSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPolyglotSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPolyglotSetup(_ plan: PolyglotSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Keep awake card, or a spoken "how's keep awake set", says the three limits. It does not start a session.
    func sayKeepAwakeSetup() {
        presentKeepAwakeSetup(speak: true)
    }

    private func answerKeepAwakeSetup(speak: Bool) -> TurnResult {
        presentKeepAwakeSetup(speak: speak)
        return TurnResult(spoken: keepAwakeSetupLine())
    }

    private func presentKeepAwakeSetup(speak: Bool) {
        let parts = keepAwakeSetupParts()
        let line = KeepAwakeSetupAsk.line(length: parts.length, floor: parts.floor, heat: parts.heat)
        let plan = KeepAwakeSetupDraw.plan(length: parts.length, floor: parts.floor, heat: parts.heat)
        buddy.idle()
        showKeepAwakeSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same reads as the Keep awake card. A missing key keeps the page default.
    /// Reading them does not start a session or take a power assertion.
    private func keepAwakeSetupParts() -> (length: String, floor: String, heat: String) {
        let defaults = UserDefaults.standard
        let minutes: Int?
        if let stored = defaults.object(forKey: "keepAwake.homeMinutes") as? Int {
            minutes = stored > 0 ? stored : nil
        } else {
            minutes = 30
        }
        let floor = defaults.object(forKey: "keepAwake.batteryFloor") as? Int ?? 10
        let hot = defaults.object(forKey: "keepAwake.endWhenHot") as? Bool ?? true
        return (KeepAwakeLength.label(minutes), KeepAwakeRules.floorLabel(floor), hot ? "On" : "Off")
    }

    private func keepAwakeSetupLine() -> String {
        let parts = keepAwakeSetupParts()
        return KeepAwakeSetupAsk.line(length: parts.length, floor: parts.floor, heat: parts.heat)
    }

    /// Draws Limits, then the length, the floor, and heat. The caller speaks the full line.
    private func showKeepAwakeSetup(_ plan: KeepAwakeSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyKeepAwakeSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyKeepAwakeSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyKeepAwakeSetup(_ plan: KeepAwakeSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Fling card, or a spoken "how's fling set", says the three choices. It does not turn Fling on.
    func sayFlingSetup() {
        presentFlingSetup(speak: true)
    }

    private func answerFlingSetup(speak: Bool) -> TurnResult {
        presentFlingSetup(speak: speak)
        return TurnResult(spoken: flingSetupLine())
    }

    private func presentFlingSetup(speak: Bool) {
        let parts = flingSetupParts()
        let line = FlingSetupAsk.line(work: parts.work, see: parts.see, save: parts.save)
        let plan = FlingSetupDraw.plan(work: parts.work, see: parts.see, save: parts.save)
        buddy.idle()
        showFlingSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// On or off, who can see this Mac, and where arrivals go. An unset value follows the catalog default.
    /// Reading them does not turn Fling on, and the Mac's name stays off the card.
    private func flingSetupParts() -> (work: String, see: String, save: String) {
        let store = SettingsStore.shared
        let work = store.bool("fling.enabled") ? "On" : "Off"
        return (work, store.string("fling.visibility"), store.string("fling.saveMode"))
    }

    private func flingSetupLine() -> String {
        let parts = flingSetupParts()
        return FlingSetupAsk.line(work: parts.work, see: parts.see, save: parts.save)
    }

    /// Draws Fling, then work, who can see it, and where arrivals go. The caller speaks the full line.
    private func showFlingSetup(_ plan: FlingSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFlingSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFlingSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFlingSetup(_ plan: FlingSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Arrange card, or a spoken "how's tiling set", says the three choices. It does not move a window.
    func sayTilingSetup() {
        presentTilingSetup(speak: true)
    }

    private func answerTilingSetup(speak: Bool) -> TurnResult {
        presentTilingSetup(speak: speak)
        return TurnResult(spoken: tilingSetupLine())
    }

    private func presentTilingSetup(speak: Bool) {
        let parts = tilingSetupParts()
        let line = TilingSetupAsk.line(work: parts.work, keys: parts.keys, ring: parts.ring)
        let plan = TilingSetupDraw.plan(work: parts.work, keys: parts.keys, ring: parts.ring)
        buddy.idle()
        showTilingSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// On or off, the key menu, and the focus ring. An unset value follows the catalog default.
    /// Reading them does not turn tiling on or move a window.
    private func tilingSetupParts() -> (work: String, keys: String, ring: String) {
        let store = SettingsStore.shared
        let work = store.bool("tiling.enabled") ? "On" : "Off"
        let ring = store.bool("tiling.focusBorder") ? "On" : "Off"
        return (work, store.string("tiling.keyBase"), ring)
    }

    private func tilingSetupLine() -> String {
        let parts = tilingSetupParts()
        return TilingSetupAsk.line(work: parts.work, keys: parts.keys, ring: parts.ring)
    }

    /// Draws Arrange, then work, the keys, and the ring. The caller speaks the full line.
    private func showTilingSetup(_ plan: TilingSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTilingSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTilingSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTilingSetup(_ plan: TilingSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Coding card, or a spoken "how's coding set", says the agent and the terminal. It does not start a session.
    func sayCodingSetup() {
        presentCodingSetup(speak: true)
    }

    private func answerCodingSetup(speak: Bool) -> TurnResult {
        presentCodingSetup(speak: speak)
        return TurnResult(spoken: codingSetupLine())
    }

    private func presentCodingSetup(speak: Bool) {
        let parts = codingSetupParts()
        let line = CodingSetupAsk.line(agent: parts.agent, terminal: parts.terminal)
        let plan = CodingSetupDraw.plan(agent: parts.agent, terminal: parts.terminal)
        buddy.idle()
        showCodingSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same titles the Coding menus show. An unknown stored value uses that menu's default.
    /// Reading them does not open a terminal.
    private func codingSetupParts() -> (agent: String, terminal: String) {
        let defaults = UserDefaults.standard
        let agent = CodingTool(rawValue: defaults.string(forKey: CodingTool.preferenceKey) ?? "")?.title ?? CodingTool.claude.title
        let terminal = TerminalApp(rawValue: defaults.string(forKey: TerminalApp.preferenceKey) ?? "")?.title ?? "Automatic"
        return (agent, terminal)
    }

    private func codingSetupLine() -> String {
        let parts = codingSetupParts()
        return CodingSetupAsk.line(agent: parts.agent, terminal: parts.terminal)
    }

    /// Draws Code, then the agent and the terminal. The caller speaks the full line.
    private func showCodingSetup(_ plan: CodingSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCodingSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCodingSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCodingSetup(_ plan: CodingSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Agent notifications card, or a spoken "how's agent notices set", says the three choices. It does not ask macOS.
    func sayNotifySetup() {
        presentNotifySetup(speak: true)
    }

    private func answerNotifySetup(speak: Bool) -> TurnResult {
        presentNotifySetup(speak: speak)
        return TurnResult(spoken: notifySetupLine())
    }

    private func presentNotifySetup(speak: Bool) {
        let parts = notifySetupParts()
        let line = NotifySetupAsk.line(errors: parts.errors, stuck: parts.stuck, quiet: parts.quiet)
        let plan = NotifySetupDraw.plan(errors: parts.errors, stuck: parts.stuck, quiet: parts.quiet)
        buddy.idle()
        showNotifySetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Errors, the stall menu, and quiet while sharing. An unset value follows the page default.
    /// Reading them does not ask macOS, and a notification title stays off the card.
    private func notifySetupParts() -> (errors: String, stuck: String, quiet: String) {
        let store = SettingsStore.shared
        let errors = store.bool("notify.errors") ? "On" : "Off"
        let quiet = ExtraPreferences.shared.quietWhileSharing ? "On" : "Off"
        return (errors, store.string("notify.stallMinutes"), quiet)
    }

    private func notifySetupLine() -> String {
        let parts = notifySetupParts()
        return NotifySetupAsk.line(errors: parts.errors, stuck: parts.stuck, quiet: parts.quiet)
    }

    /// Draws Notify, then errors, the stall, and quiet while sharing. The caller speaks the full line.
    private func showNotifySetup(_ plan: NotifySetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotifySetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotifySetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotifySetup(_ plan: NotifySetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Receiving card, or a spoken "how's receiving set", says which switches are on. It does not turn Fling on.
    func sayReceiveSetup() {
        presentReceiveSetup(speak: true)
    }

    private func answerReceiveSetup(speak: Bool) -> TurnResult {
        presentReceiveSetup(speak: speak)
        return TurnResult(spoken: receiveSetupLine())
    }

    private func presentReceiveSetup(speak: Bool) {
        let words = receiveSetupWords()
        let line = ReceiveSetupAsk.line(words: words)
        let plan = ReceiveSetupDraw.plan(words: words)
        buddy.idle()
        showReceiveSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Accept, closed, links, papers, then glow, for each switch that is on.
    /// An unset value follows the catalog default. Reading them does not turn Fling on.
    private func receiveSetupWords() -> [String] {
        let store = SettingsStore.shared
        let pairs = [
            ("fling.autoAcceptPaired", "Accept"),
            ("fling.receiveInBackground", "Closed"),
            ("fling.openLinks", "Links"),
            ("fling.papers", "Papers"),
            ("lights.fling", "Glow"),
        ]
        return pairs.compactMap { store.bool($0.0) ? $0.1 : nil }
    }

    private func receiveSetupLine() -> String {
        ReceiveSetupAsk.line(words: receiveSetupWords())
    }

    /// Draws Receive, then up to four switches that are on, or None. The caller speaks the full line.
    private func showReceiveSetup(_ plan: ReceiveSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyReceiveSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyReceiveSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyReceiveSetup(_ plan: ReceiveSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Zeus and Beamer card, or a spoken "how's beamer set", says the three choices. It does not start Beamer.
    func sayBeamerSetup() {
        presentBeamerSetup(speak: true)
    }

    private func answerBeamerSetup(speak: Bool) -> TurnResult {
        presentBeamerSetup(speak: speak)
        return TurnResult(spoken: beamerSetupLine())
    }

    private func presentBeamerSetup(speak: Bool) {
        let parts = beamerSetupParts()
        let line = BeamerSetupAsk.line(start: parts.start, light: parts.light, tab: parts.tab)
        let plan = BeamerSetupDraw.plan(start: parts.start, light: parts.light, tab: parts.tab)
        buddy.idle()
        showBeamerSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Start, the crossing light, and the Continuity tab. An unset switch follows the catalog default.
    /// Reading them does not start Beamer or move the keyboard. Machine names stay off the card.
    private func beamerSetupParts() -> (start: String, light: String, tab: String) {
        let store = SettingsStore.shared
        let start = store.bool("beamer.autoStart") ? "On" : "Off"
        let light = store.bool("beamer.cue") ? "On" : "Off"
        let tab = BeamerSetupVoice.continuityOn() ? "On" : "Off"
        return (start, light, tab)
    }

    private func beamerSetupLine() -> String {
        let parts = beamerSetupParts()
        return BeamerSetupAsk.line(start: parts.start, light: parts.light, tab: parts.tab)
    }

    /// Draws Link, then start, the crossing light, and the tab. The caller speaks the full line.
    private func showBeamerSetup(_ plan: BeamerSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBeamerSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBeamerSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBeamerSetup(_ plan: BeamerSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Captions card, or a spoken "how's captions set", says the original and the size. It does not start Polyglot.
    func sayCaptionSetup() {
        presentCaptionSetup(speak: true)
    }

    private func answerCaptionSetup(speak: Bool) -> TurnResult {
        presentCaptionSetup(speak: speak)
        return TurnResult(spoken: captionSetupLine())
    }

    private func presentCaptionSetup(speak: Bool) {
        let parts = captionSetupParts()
        let line = CaptionSetupAsk.line(original: parts.original, size: parts.size)
        let plan = CaptionSetupDraw.plan(original: parts.original, size: parts.size)
        buddy.idle()
        showCaptionSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The original switch and the size menu. An unknown stored size is Medium, the same as the menu.
    /// Reading them does not start Polyglot or pop the captions out. Caption text stays off the card.
    private func captionSetupParts() -> (original: String, size: String) {
        let settings = PolyglotSettings.shared
        let original = settings.showOriginal ? "On" : "Off"
        return (original, settings.captionSize.title)
    }

    private func captionSetupLine() -> String {
        let parts = captionSetupParts()
        return CaptionSetupAsk.line(original: parts.original, size: parts.size)
    }

    /// Draws Caption, then the original and the size. The caller speaks the full line.
    private func showCaptionSetup(_ plan: CaptionSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCaptionSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCaptionSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCaptionSetup(_ plan: CaptionSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The events card, or a spoken "which events play a sound", says the three switches. It does not play a sound.
    func saySoundEvents() {
        presentSoundEvents(speak: true)
    }

    private func answerSoundEvents(speak: Bool) -> TurnResult {
        presentSoundEvents(speak: speak)
        return TurnResult(spoken: soundEventsLine())
    }

    private func presentSoundEvents(speak: Bool) {
        let parts = soundEventsParts()
        let line = SoundEventsAsk.line(requests: parts.requests, done: parts.done, todo: parts.todo)
        let plan = SoundEventsDraw.plan(requests: parts.requests, done: parts.done, todo: parts.todo)
        buddy.idle()
        showSoundEvents(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Requests, completion, and a checked to-do. An unset switch follows the page default, on.
    /// Reading them does not play a cue.
    private func soundEventsParts() -> (requests: String, done: String, todo: String) {
        let prefs = ExtraPreferences.shared
        let requests = prefs.soundApproval ? "On" : "Off"
        let done = prefs.soundDone ? "On" : "Off"
        let todo = prefs.soundTodo ? "On" : "Off"
        return (requests, done, todo)
    }

    private func soundEventsLine() -> String {
        let parts = soundEventsParts()
        return SoundEventsAsk.line(requests: parts.requests, done: parts.done, todo: parts.todo)
    }

    /// Draws Events, then requests, completion, and a checked to-do. The caller speaks the full line.
    private func showSoundEvents(_ plan: SoundEventsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySoundEvents(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySoundEvents(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySoundEvents(_ plan: SoundEventsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Other apps card, or a spoken "how's other apps set", says the three switches. It does not read Notification Center.
    func sayOtherApps() {
        presentOtherApps(speak: true)
    }

    private func answerOtherApps(speak: Bool) -> TurnResult {
        presentOtherApps(speak: speak)
        return TurnResult(spoken: otherAppsLine())
    }

    private func presentOtherApps(speak: Bool) {
        let parts = otherAppsParts()
        let line = OtherAppsAsk.line(apps: parts.apps, peek: parts.peek, details: parts.details)
        let plan = OtherAppsDraw.plan(apps: parts.apps, peek: parts.peek, details: parts.details)
        buddy.idle()
        showOtherApps(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The mirror, the peek, and details. An unset peek follows the catalog default, on.
    /// The mirror is the same key the Other apps switch stores. Reading it does not scan Notification Center.
    private func otherAppsParts() -> (apps: String, peek: String, details: String) {
        let apps = UserDefaults.standard.bool(forKey: "notifications.mirror") ? "On" : "Off"
        let store = SettingsStore.shared
        let peek = store.bool("notify.peek") ? "On" : "Off"
        let details = store.bool("notify.peekDetails") ? "On" : "Off"
        return (apps, peek, details)
    }

    private func otherAppsLine() -> String {
        let parts = otherAppsParts()
        return OtherAppsAsk.line(apps: parts.apps, peek: parts.peek, details: parts.details)
    }

    /// Draws Apps, then the mirror, the peek, and details. The caller speaks the full line.
    private func showOtherApps(_ plan: OtherAppsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyOtherApps(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyOtherApps(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyOtherApps(_ plan: OtherAppsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Home style rows, or a spoken "how's home styled", say the four styles. They do not change the cards.
    func sayHomeStyles() {
        presentHomeStyles(speak: true)
    }

    private func answerHomeStyles(speak: Bool) -> TurnResult {
        presentHomeStyles(speak: speak)
        return TurnResult(spoken: homeStylesLine())
    }

    private func presentHomeStyles(speak: Bool) {
        let parts = homeStylesParts()
        let line = HomeStylesAsk.line(clock: parts.clock, music: parts.music, weather: parts.weather, calendar: parts.calendar)
        let plan = HomeStylesDraw.plan(clock: parts.clock, music: parts.music, weather: parts.weather, calendar: parts.calendar)
        buddy.idle()
        showHomeStyles(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The four style menus. An unset value follows the catalog default.
    /// Reading them does not change which Home cards are showing.
    private func homeStylesParts() -> (clock: String, music: String, weather: String, calendar: String) {
        let store = SettingsStore.shared
        return (
            store.string("home.variant.clock"),
            store.string("home.variant.music"),
            store.string("home.variant.weather"),
            store.string("home.variant.calendar")
        )
    }

    private func homeStylesLine() -> String {
        let parts = homeStylesParts()
        return HomeStylesAsk.line(clock: parts.clock, music: parts.music, weather: parts.weather, calendar: parts.calendar)
    }

    /// Draws Styles, then clock, music, weather, and calendar. The caller speaks the full line.
    private func showHomeStyles(_ plan: HomeStylesDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHomeStyles(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHomeStyles(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHomeStyles(_ plan: HomeStylesDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Weather card, or a spoken "where's the forecast from", says the city and the units. It does not fetch a forecast.
    func sayWeatherPlace() {
        presentWeatherPlace(speak: true)
    }

    private func answerWeatherPlace(speak: Bool) -> TurnResult {
        presentWeatherPlace(speak: speak)
        return TurnResult(spoken: weatherPlaceLine())
    }

    private func presentWeatherPlace(speak: Bool) {
        let parts = weatherPlaceParts()
        let line = WeatherPlaceAsk.line(place: parts.place, units: parts.units)
        let plan = WeatherPlaceDraw.plan(place: parts.place, units: parts.units)
        buddy.idle()
        showWeatherPlace(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The city field and the units menu. An empty city is None. A missing units key follows the page: Celsius outside the US.
    /// Reading them does not fetch a forecast.
    private func weatherPlaceParts() -> (place: String, units: String) {
        let raw = UserDefaults.standard.string(forKey: "topBar.weatherCity") ?? ""
        let flat = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let place = flat.isEmpty ? "None" : flat
        let celsius: Bool
        if let stored = UserDefaults.standard.object(forKey: "topBar.celsius") as? Bool {
            celsius = stored
        } else {
            celsius = Locale.current.measurementSystem != .us
        }
        return (place, celsius ? "\u{00B0}C" : "\u{00B0}F")
    }

    private func weatherPlaceLine() -> String {
        let parts = weatherPlaceParts()
        return WeatherPlaceAsk.line(place: parts.place, units: parts.units)
    }

    /// Draws Forecast, then the place and the units. The caller speaks the full line.
    private func showWeatherPlace(_ plan: WeatherPlaceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWeatherPlace(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWeatherPlace(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWeatherPlace(_ plan: WeatherPlaceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Insomnia cards, or a spoken "how's insomnia set", say the three switches. They do not install the rule.
    func sayInsomniaSetup() {
        presentInsomniaSetup(speak: true)
    }

    private func answerInsomniaSetup(speak: Bool) -> TurnResult {
        presentInsomniaSetup(speak: speak)
        return TurnResult(spoken: insomniaSetupLine())
    }

    private func presentInsomniaSetup(speak: Bool) {
        let parts = insomniaSetupParts()
        let line = InsomniaSetupAsk.line(lid: parts.lid, mute: parts.mute, power: parts.power)
        let plan = InsomniaSetupDraw.plan(lid: parts.lid, mute: parts.mute, power: parts.power)
        buddy.idle()
        showInsomniaSetup(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The same stored switches the Insomnia page keeps. A missing key follows the page default, on.
    /// Reading them does not install the admin rule, close the lid, or read the hotspot.
    private func insomniaSetupParts() -> (lid: String, mute: String, power: String) {
        let defaults = UserDefaults.standard
        func on(_ key: String) -> String {
            let stored = defaults.object(forKey: key) as? Bool ?? true
            return stored ? "On" : "Off"
        }
        return (on("insomnia.lidClosed"), on("insomnia.mute"), on("insomnia.lowPower"))
    }

    private func insomniaSetupLine() -> String {
        let parts = insomniaSetupParts()
        return InsomniaSetupAsk.line(lid: parts.lid, mute: parts.mute, power: parts.power)
    }

    /// Draws Sleep, then lid-closed mode, mute, and Low Power Mode. The caller speaks the full line.
    private func showInsomniaSetup(_ plan: InsomniaSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyInsomniaSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyInsomniaSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyInsomniaSetup(_ plan: InsomniaSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Modes card, or a spoken "which dictation mode", says the built-in mode and switch by app. It does not start dictation.
    func sayDictationMode() {
        presentDictationMode(speak: true)
    }

    private func answerDictationMode(speak: Bool) -> TurnResult {
        presentDictationMode(speak: speak)
        return TurnResult(spoken: dictationModeLine())
    }

    private func presentDictationMode(speak: Bool) {
        let parts = dictationModeParts()
        let line = DictationModeAsk.line(mode: parts.mode, apps: parts.apps)
        let plan = DictationModeDraw.plan(mode: parts.mode, apps: parts.apps)
        buddy.idle()
        showDictationMode(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The chosen built-in mode and switch by app. An unset mode is Voice. A custom mode stays unread.
    /// Reading them does not start dictation, and a mode's instructions stay off the card.
    private func dictationModeParts() -> (mode: String, apps: String) {
        let key = UserDefaults.standard.string(forKey: "dictation.mode") ?? "voice"
        let mode = DictationMode.builtIns.first { $0.key == key }?.name ?? key
        let apps = (UserDefaults.standard.object(forKey: "dictation.autoSwitch") as? Bool ?? false) ? "On" : "Off"
        return (mode, apps)
    }

    private func dictationModeLine() -> String {
        let parts = dictationModeParts()
        return DictationModeAsk.line(mode: parts.mode, apps: parts.apps)
    }

    /// Draws Mode, then the writing mode and switch by app. The caller speaks the full line.
    private func showDictationMode(_ plan: DictationModeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDictationMode(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDictationMode(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDictationMode(_ plan: DictationModeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Voice glow card, or a spoken "how's the voice glow set", says the switch and the colors. It does not start dictation.
    func sayVoiceGlow() {
        presentVoiceGlow(speak: true)
    }

    private func answerVoiceGlow(speak: Bool) -> TurnResult {
        presentVoiceGlow(speak: speak)
        return TurnResult(spoken: voiceGlowLine())
    }

    private func presentVoiceGlow(speak: Bool) {
        let parts = voiceGlowParts()
        let line = VoiceGlowAsk.line(work: parts.work, color: parts.color)
        let plan = VoiceGlowDraw.plan(work: parts.work, color: parts.color)
        buddy.idle()
        showVoiceGlow(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// On or off, and the color menu. An unset switch is on. An unknown stored color is Colorful, the same as the menu.
    /// Reading them does not start dictation.
    private func voiceGlowParts() -> (work: String, color: String) {
        let work = (UserDefaults.standard.object(forKey: VoiceGlowSettings.enabledKey) as? Bool ?? true) ? "On" : "Off"
        let color = VoiceGlowVariant.resolve(UserDefaults.standard.string(forKey: VoiceGlowSettings.variantKey)).title
        return (work, color)
    }

    private func voiceGlowLine() -> String {
        let parts = voiceGlowParts()
        return VoiceGlowAsk.line(work: parts.work, color: parts.color)
    }

    /// Draws Glow, then the switch and the color set. The caller speaks the full line.
    private func showVoiceGlow(_ plan: VoiceGlowDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVoiceGlow(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVoiceGlow(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVoiceGlow(_ plan: VoiceGlowDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Recording card, or a spoken "how's recording set", says the four switches. It does not start dictation.
    func sayDictationRecord() {
        presentDictationRecord(speak: true)
    }

    private func answerDictationRecord(speak: Bool) -> TurnResult {
        presentDictationRecord(speak: speak)
        return TurnResult(spoken: dictationRecordLine())
    }

    private func presentDictationRecord(speak: Bool) {
        let parts = dictationRecordParts()
        let line = DictationRecordAsk.line(pill: parts.pill, check: parts.check, music: parts.music, type: parts.type)
        let plan = DictationRecordDraw.plan(pill: parts.pill, check: parts.check, music: parts.music, type: parts.type)
        buddy.idle()
        showDictationRecord(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The pill, the check, pause music, and type instead of paste. A missing key follows the page default.
    /// Reading them does not start dictation.
    private func dictationRecordParts() -> (pill: String, check: String, music: String, type: String) {
        func flag(_ key: String, default fallback: Bool) -> String {
            let stored = UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
            return stored ? "On" : "Off"
        }
        return (
            flag(RecorderPill.enabledKey, default: true),
            flag("dictation.preview", default: false),
            flag("dictation.pauseMedia", default: true),
            flag("dictation.alwaysType", default: false)
        )
    }

    private func dictationRecordLine() -> String {
        let parts = dictationRecordParts()
        return DictationRecordAsk.line(pill: parts.pill, check: parts.check, music: parts.music, type: parts.type)
    }

    /// Draws Record, then the four switches. The caller speaks the full line.
    private func showDictationRecord(_ plan: DictationRecordDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDictationRecord(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDictationRecord(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDictationRecord(_ plan: DictationRecordDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Agents in tmux card, or a spoken "how's the nudge set", says the switch and the wait. It does not send a nudge.
    func sayAgentNudge() {
        presentAgentNudge(speak: true)
    }

    private func answerAgentNudge(speak: Bool) -> TurnResult {
        presentAgentNudge(speak: speak)
        return TurnResult(spoken: agentNudgeLine())
    }

    private func presentAgentNudge(speak: Bool) {
        let parts = agentNudgeParts()
        let line = AgentNudgeAsk.line(work: parts.work, after: parts.after)
        let plan = AgentNudgeDraw.plan(work: parts.work, after: parts.after)
        buddy.idle()
        showAgentNudge(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The nudge switch and the Stalled after menu. A missing switch is off. A missing wait is 10 min.
    /// Reading them does not send a nudge or read the hotspot.
    private func agentNudgeParts() -> (work: String, after: String) {
        let work = (UserDefaults.standard.object(forKey: "insomnia.nudge") as? Bool ?? false) ? "On" : "Off"
        let minutes = UserDefaults.standard.object(forKey: "insomnia.nudgeMinutes") as? Int ?? 10
        return (work, "\(minutes) min")
    }

    private func agentNudgeLine() -> String {
        let parts = agentNudgeParts()
        return AgentNudgeAsk.line(work: parts.work, after: parts.after)
    }

    /// Draws Nudge, then the switch and the wait. The caller speaks the full line.
    private func showAgentNudge(_ plan: AgentNudgeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgentNudge(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgentNudge(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgentNudge(_ plan: AgentNudgeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Home frame row, or a spoken "how's the home frame", says the frame and the Physical finish. It does not change the pictures.
    func sayHomeFrame() {
        presentHomeFrame(speak: true)
    }

    private func answerHomeFrame(speak: Bool) -> TurnResult {
        presentHomeFrame(speak: speak)
        return TurnResult(spoken: homeFrameLine())
    }

    private func presentHomeFrame(speak: Bool) {
        let parts = homeFrameParts()
        let line = HomeFrameAsk.line(frame: parts.frame, finish: parts.finish)
        let plan = HomeFrameDraw.plan(frame: parts.frame, finish: parts.finish)
        buddy.idle()
        showHomeFrame(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The Home style menu and the Physical finish menu. An old "Same everywhere" shows as Same all.
    /// Reading them does not change the card pictures.
    private func homeFrameParts() -> (frame: String, finish: String) {
        let store = SettingsStore.shared
        let raw = store.string("appearance.physicalFinish")
        let finish = raw == "Same everywhere" ? "Same all" : raw
        return (store.string("appearance.homeStyle"), finish)
    }

    private func homeFrameLine() -> String {
        let parts = homeFrameParts()
        return HomeFrameAsk.line(frame: parts.frame, finish: parts.finish)
    }

    /// Draws Frame, then the Home frame and the Physical finish. The caller speaks the full line.
    private func showHomeFrame(_ plan: HomeFrameDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHomeFrame(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHomeFrame(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHomeFrame(_ plan: HomeFrameDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Screen card, or a spoken "how's the screen corners", says the rounding and the size. It does not move a window.
    func sayScreenCorners() {
        presentScreenCorners(speak: true)
    }

    private func answerScreenCorners(speak: Bool) -> TurnResult {
        presentScreenCorners(speak: speak)
        return TurnResult(spoken: screenCornersLine())
    }

    private func presentScreenCorners(speak: Bool) {
        let parts = screenCornerParts()
        let line = ScreenCornerAsk.line(round: parts.round, size: parts.size)
        let plan = ScreenCornerDraw.plan(round: parts.round, size: parts.size)
        buddy.idle()
        showScreenCorners(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Rounding and the corner-size menu. An unset switch is off. An unset size is Medium.
    /// Reading them does not move a window.
    private func screenCornerParts() -> (round: String, size: String) {
        let store = SettingsStore.shared
        let round = store.bool("screen.roundBottomCorners") ? "On" : "Off"
        return (round, store.string("screen.cornerRadius"))
    }

    private func screenCornersLine() -> String {
        let parts = screenCornerParts()
        return ScreenCornerAsk.line(round: parts.round, size: parts.size)
    }

    /// Draws Corners, then rounding and the size. The caller speaks the full line.
    private func showScreenCorners(_ plan: ScreenCornerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScreenCorners(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScreenCorners(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScreenCorners(_ plan: ScreenCornerDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Card details card, or a spoken "how's the notch close", says auto-hide and the delay. It does not close the notch.
    func sayNotchClose() {
        presentNotchClose(speak: true)
    }

    private func answerNotchClose(speak: Bool) -> TurnResult {
        presentNotchClose(speak: speak)
        return TurnResult(spoken: notchCloseLine())
    }

    private func presentNotchClose(speak: Bool) {
        let parts = notchCloseParts()
        let line = NotchCloseAsk.line(hide: parts.hide, wait: parts.wait)
        let plan = NotchCloseDraw.plan(hide: parts.hide, wait: parts.wait)
        buddy.idle()
        showNotchClose(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Auto-hide and the close-delay menu. An unset switch is on. An unset delay is 0.5 s.
    /// Reading them does not open or close the notch.
    private func notchCloseParts() -> (hide: String, wait: String) {
        let store = SettingsStore.shared
        let hide = store.bool("notch.autoHide") ? "On" : "Off"
        return (hide, store.string("notch.closeDelay"))
    }

    private func notchCloseLine() -> String {
        let parts = notchCloseParts()
        return NotchCloseAsk.line(hide: parts.hide, wait: parts.wait)
    }

    /// Draws Close, then auto-hide and the delay. The caller speaks the full line.
    private func showNotchClose(_ plan: NotchCloseDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotchClose(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotchClose(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotchClose(_ plan: NotchCloseDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Everyday actions rows, or a spoken "which everyday lights", say which are on. They do not change them.
    func sayEverydayLights() {
        presentEverydayLights(speak: true)
    }

    private func answerEverydayLights(speak: Bool) -> TurnResult {
        presentEverydayLights(speak: speak)
        return TurnResult(spoken: everydayLightsLine())
    }

    private func presentEverydayLights(speak: Bool) {
        let words = everydayLightWords()
        let line = EverydayLightsAsk.line(words: words)
        let plan = EverydayLightsDraw.plan(words: words)
        buddy.idle()
        showEverydayLights(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Battery through caps, for each light that is on. An unset value follows the catalog default, on.
    /// Reading them does not change the lights.
    private func everydayLightWords() -> [String] {
        let store = SettingsStore.shared
        let pairs = [
            ("lights.battery", "Battery"),
            ("lights.rain", "Rain"),
            ("lights.timer", "Timer"),
            ("lights.micGlow", "Mic"),
            ("lights.reminderGlow", "Reminder"),
            ("lights.copy", "Copy"),
            ("lights.shelf", "Shelf"),
            ("lights.capsLock", "Caps"),
        ]
        return pairs.compactMap { store.bool($0.0) ? $0.1 : nil }
    }

    private func everydayLightsLine() -> String {
        EverydayLightsAsk.line(words: everydayLightWords())
    }

    /// Draws Moments, then up to four lights that are on, or None. The caller speaks the full line.
    private func showEverydayLights(_ plan: EverydayLightsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyEverydayLights(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyEverydayLights(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyEverydayLights(_ plan: EverydayLightsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The halo arm row, or a spoken "how's the halo arm", says the arm and the island. It does not change the light.
    func sayHaloArm() {
        presentHaloArm(speak: true)
    }

    private func answerHaloArm(speak: Bool) -> TurnResult {
        presentHaloArm(speak: speak)
        return TurnResult(spoken: haloArmLine())
    }

    private func presentHaloArm(speak: Bool) {
        let parts = haloArmParts()
        let line = HaloArmAsk.line(arm: parts.arm, island: parts.island)
        let plan = HaloArmDraw.plan(arm: parts.arm, island: parts.island)
        buddy.idle()
        showHaloArm(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The arm menu and the island menu. An unset value follows the catalog default.
    /// Reading them does not change the light picture.
    private func haloArmParts() -> (arm: String, island: String) {
        let store = SettingsStore.shared
        return (store.string("halo.armWidth"), store.string(NotchBackground.settingID))
    }

    private func haloArmLine() -> String {
        let parts = haloArmParts()
        return HaloArmAsk.line(arm: parts.arm, island: parts.island)
    }

    /// Draws Reach, then the arm and the island. The caller speaks the full line.
    private func showHaloArm(_ plan: HaloArmDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHaloArm(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHaloArm(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHaloArm(_ plan: HaloArmDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Music rows, or a spoken "which music lights", say the four lights. They do not start playback.
    func sayMusicLights() {
        presentMusicLights(speak: true)
    }

    private func answerMusicLights(speak: Bool) -> TurnResult {
        presentMusicLights(speak: speak)
        return TurnResult(spoken: musicLightsLine())
    }

    private func presentMusicLights(speak: Bool) {
        let parts = musicLightsParts()
        let line = MusicLightsAsk.line(wave: parts.wave, outline: parts.outline, words: parts.words, sound: parts.sound)
        let plan = MusicLightsDraw.plan(wave: parts.wave, outline: parts.outline, words: parts.words, sound: parts.sound)
        buddy.idle()
        showMusicLights(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The wave, the outline, word lights, and the sound reaction. A missing wave is on. Sound reaction is off until it is turned on.
    /// Reading them does not start playback or ask for system audio.
    private func musicLightsParts() -> (wave: String, outline: String, words: String, sound: String) {
        let store = SettingsStore.shared
        func flag(_ on: Bool) -> String { on ? "On" : "Off" }
        return (
            flag(MusicLightsVoice.wingsOn()),
            flag(store.bool("lights.musicProgress")),
            flag(store.bool("lyrics.wordByWord")),
            flag(store.bool("lights.liveSpectrum"))
        )
    }

    private func musicLightsLine() -> String {
        let parts = musicLightsParts()
        return MusicLightsAsk.line(wave: parts.wave, outline: parts.outline, words: parts.words, sound: parts.sound)
    }

    /// Draws Wave, then the four music lights. The caller speaks the full line.
    private func showMusicLights(_ plan: MusicLightsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMusicLights(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMusicLights(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMusicLights(_ plan: MusicLightsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The Running card, or a spoken "how's the running card set", says the look, how it opens, and the hover delay. It does not open the notch.
    func sayRunningCard() {
        presentRunningCard(speak: true)
    }

    private func answerRunningCard(speak: Bool) -> TurnResult {
        presentRunningCard(speak: speak)
        return TurnResult(spoken: runningCardLine())
    }

    private func presentRunningCard(speak: Bool) {
        let parts = runningCardParts()
        let line = RunningCardAsk.line(look: parts.look, open: parts.open, wait: parts.wait)
        let plan = RunningCardDraw.plan(look: parts.look, open: parts.open, wait: parts.wait)
        buddy.idle()
        showRunningCard(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The running-card pictures, Open the notch on, and the hover delay. An unset value follows the catalog default.
    /// Reading them does not open the notch.
    private func runningCardParts() -> (look: String, open: String, wait: String) {
        let store = SettingsStore.shared
        return (store.string("appearance.runningCard"), store.string("notch.openTrigger"), store.string("notch.openDelay"))
    }

    private func runningCardLine() -> String {
        let parts = runningCardParts()
        return RunningCardAsk.line(look: parts.look, open: parts.open, wait: parts.wait)
    }

    /// Draws Running, then the look, how it opens, and the hover delay. The caller speaks the full line.
    private func showRunningCard(_ plan: RunningCardDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRunningCard(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRunningCard(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRunningCard(_ plan: RunningCardDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The voice style rows, or a spoken "how's the voice styled", say replies, personality, the orb, and the effect. They do not change the voice.
    func sayVoiceStyle() {
        presentVoiceStyle(speak: true)
    }

    private func answerVoiceStyle(speak: Bool) -> TurnResult {
        presentVoiceStyle(speak: speak)
        return TurnResult(spoken: voiceStyleLine())
    }

    private func presentVoiceStyle(speak: Bool) {
        let parts = voiceStyleParts()
        let line = VoiceStyleAsk.line(speak: parts.speak, tone: parts.tone, orb: parts.orb, effect: parts.effect)
        let plan = VoiceStyleDraw.plan(speak: parts.speak, tone: parts.tone, orb: parts.orb, effect: parts.effect)
        buddy.idle()
        showVoiceStyle(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Spoken replies, personality, the orb, and the Ultron effect. An unknown personality is Ultron. An unknown orb is Mascot.
    /// Reading them does not change the voice.
    private func voiceStyleParts() -> (speak: String, tone: String, orb: String, effect: String) {
        let speak = SettingsStore.shared.bool("voice.speakReplies") ? "On" : "Off"
        let tone = ZeusPersonality.current().title
        let orb = VoiceOrbStyle.resolve(UserDefaults.standard.string(forKey: VoiceOrbStyle.defaultsKey)).title
        let effect = UltronVoiceEffect.enabled ? "On" : "Off"
        return (speak, tone, orb, effect)
    }

    private func voiceStyleLine() -> String {
        let parts = voiceStyleParts()
        return VoiceStyleAsk.line(speak: parts.speak, tone: parts.tone, orb: parts.orb, effect: parts.effect)
    }

    /// Draws Tone, then speech, personality, the orb, and the effect. The caller speaks the full line.
    private func showVoiceStyle(_ plan: VoiceStyleDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVoiceStyle(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVoiceStyle(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVoiceStyle(_ plan: VoiceStyleDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Lock and wake, or a spoken "how's lock and wake set", says the switch and whether each chime is built in or chosen. It does not play a chime.
    func sayLockChimes() {
        presentLockChimes(speak: true)
    }

    private func answerLockChimes(speak: Bool) -> TurnResult {
        presentLockChimes(speak: speak)
        return TurnResult(spoken: lockChimeLine())
    }

    private func presentLockChimes(speak: Bool) {
        let parts = lockChimeParts()
        let line = LockChimeAsk.line(work: parts.work, lock: parts.lock, wake: parts.wake)
        let plan = LockChimeDraw.plan(work: parts.work, lock: parts.lock, wake: parts.wake)
        buddy.idle()
        showLockChimes(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// The lock and wake switch, and Built-in when a path is empty. A chosen file is named only as Chosen.
    /// Reading them does not play a chime.
    private func lockChimeParts() -> (work: String, lock: String, wake: String) {
        let store = SettingsStore.shared
        func kind(_ id: String) -> String {
            store.string(id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Built-in" : "Chosen"
        }
        return (store.bool(ChimeSettingsKey.enabled) ? "On" : "Off", kind(ChimeSettingsKey.closePath), kind(ChimeSettingsKey.openPath))
    }

    private func lockChimeLine() -> String {
        let parts = lockChimeParts()
        return LockChimeAsk.line(work: parts.work, lock: parts.lock, wake: parts.wake)
    }

    /// Draws Chimes, then the switch, the lock sound, and the wake sound. The caller speaks the full line.
    private func showLockChimes(_ plan: LockChimeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLockChimes(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLockChimes(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLockChimes(_ plan: LockChimeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The notch reads the day aloud. The board built for that brief is drawn while Zeus says it.
    func sayTodayBrief(_ text: String) {
        guard let plan = TodayController.shared.board else {
            say(text)
            return
        }
        showTodayBoard(plan, speak: true)
        say(text)
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws today's brief on the display under the pointer: Today, then the calendar, the to-dos, and the weather.
    /// The caller speaks the full brief. The marks still appear when that speech is off.
    private func showTodayBoard(_ plan: TodayBoardDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTodayBoard(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTodayBoard(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTodayBoard(_ plan: TodayBoardDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a coding-agent start on the display under the pointer: Building, then the tool, then the task.
    /// The caller speaks the full line. The marks still appear when that speech is off.
    private func showAgentStart(_ plan: AgentStartDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgentStart(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgentStart(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgentStart(_ plan: AgentStartDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A clock time for a timed event, or "All day" when the request named a day and no hour.
    private static func eventWhen(_ event: CalendarQuickAdd.Parsed) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: event.start)
    }

    /// The notch added an event. The screen shows Calendar, then the title, then the time, while Zeus says so.
    func sayAddedEvent(_ event: CalendarQuickAdd.Parsed) {
        let when = Self.eventWhen(event)
        let line = "Added \(event.title) to your calendar."
        guard let plan = CalendarEventDraw.plan(title: event.title, when: when) else {
            say(line)
            return
        }
        showCalendarEvent(plan, speak: true)
        say(line)
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// A notch add that did not finish. Access and calendar failures use their cards. Other notes stay on the field.
    func sayCalendarProblem(_ line: String) {
        if let visual = CalendarAccessDraw.from(line: line) {
            showCalendarAccess(visual, speak: true)
            say(line)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = CalendarFailDraw.from(line: line) {
            showCalendarFail(visual, speak: true)
            say(line)
            buddy.showCaption(visual.boltCaption(at: 0))
        }
    }

    /// Draws a calendar event on the display under the pointer: the word Calendar, then the title, then the time.
    /// The caller speaks the full line. The marks still appear when that speech is off.
    private func showCalendarEvent(_ plan: CalendarEventDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCalendarEvent(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCalendarEvent(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCalendarEvent(_ plan: CalendarEventDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a to-do Zeus marked done, or could not find, under the pointer.
    /// The caller speaks the full line. A to-do that was just added is not this card.
    private func showTodoDone(_ plan: TodoDoneDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTodoDone(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTodoDone(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTodoDone(_ plan: TodoDoneDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws added to-dos on the display under the pointer, one title at a time.
    /// The caller speaks the full line. The marks still appear when that speech is off.
    private func showTodoList(_ plan: TodoListDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTodoList(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTodoList(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTodoList(_ plan: TodoListDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the short local answer on the display under the pointer. The caller speaks the full line.
    private func showLocalAnswer(_ plan: LocalAnswerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        presenter.reveal(sentence: 0, token: token)
        buddy.flight(to: boltScreen(plan.guide, shot: shot), label: plan.bolt)
        explainReveal = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
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
            if let visual = FileFoundDraw.missing() {
                showFileFound(visual, speak: speak)
                if speak { say(missing) } else { buddy.showCaption(missing); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if speak {
                say(missing)
            } else {
                buddy.showCaption(missing)
                buddy.hideCaption()
            }
            remember(transcript, missing)
            return TurnResult(spoken: missing)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let answer = "Opening \(name)."
        buddy.idle()
        if let visual = FileFoundDraw.plan(name: name) {
            showFileFound(visual, speak: speak)
            if speak { say(answer) } else { buddy.showCaption(answer); buddy.hideCaption() }
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if speak {
            say(answer)
        } else {
            buddy.showCaption(answer)
            buddy.hideCaption()
        }
        remember(transcript, answer)
        return TurnResult(spoken: answer, actions: ["files \(path)"])
    }

    /// Everything answered without the LLM, in order: local rules (`FastIntent`), the to-do and
    /// brief phrases (`LocalTurns`), then the decision engine (Jev). nil means "LLM".
    private func understand(_ transcript: String, finalAt: ContinuousClock.Instant, speak: Bool) async -> TurnResult? {
        if let command = FocusSessionAsk.command(in: transcript) {
            if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
            let result = performFocus(command, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        let fast = FastPath.shared
        if let plan = fast.confirmedPlan(for: transcript) {
            return await perform(plan, engine: "Rules", transcript: transcript, finalAt: finalAt, speak: speak)
        }
        switch fast.rules(transcript) {
        case .hit(let plan, let engine): return await perform(plan, engine: engine, transcript: transcript, finalAt: finalAt, speak: speak)
        case .ask(let question, let engine): return askBack(question, engine: engine, transcript: transcript, speak: speak)
        case .miss: break
        }
        if NowPlayingAsk.matches(transcript) {
            let result = answerNowPlaying(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if WeatherAsk.matches(transcript) {
            let result = answerWeather(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if BatteryAsk.matches(transcript) {
            let result = answerBattery(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NextEventAsk.matches(transcript) {
            let result = answerNextEvent(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if MeetingAsk.matches(transcript) {
            if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
            let result = joinSpokenMeeting(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if let body = ReminderAsk.body(in: transcript) {
            if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
            let result = addSpokenReminder(body, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if let command = KeepAwakeAsk.command(in: transcript) {
            if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
            let result = performKeepAwake(command, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ClockAsk.matches(transcript) {
            let result = answerClock(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if let city = CityTimeAsk.city(in: transcript) {
            let result = answerCityTime(city, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CountdownAsk.matches(transcript) {
            let result = answerCountdown(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DateAsk.matches(transcript) {
            let result = answerDate(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NoteAsk.matches(transcript) {
            let result = answerNote(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if AgentStatusAsk.matches(transcript) {
            let result = answerAgents(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if TimerLeftAsk.matches(transcript) {
            let result = answerTimeLeft(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NextReminderAsk.matches(transcript) {
            let result = answerNextReminder(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if AlertStatusAsk.matches(transcript) {
            let result = answerAlerts(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if TodoCountAsk.matches(transcript) {
            let result = answerTodoCount(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if VolumeLevelAsk.matches(transcript) {
            let result = answerVolume(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if BrightnessLevelAsk.matches(transcript) {
            let result = answerBrightness(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if AgendaAsk.matches(transcript) {
            let result = answerAgenda(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ShelfAsk.matches(transcript) {
            let result = answerShelf(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if RainAsk.matches(transcript) {
            let result = answerRain(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if WeekAsk.matches(transcript) {
            let result = answerWeek(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ClipboardCountAsk.matches(transcript) {
            let result = answerClipboard(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if FrontAppAsk.matches(transcript) {
            let result = answerFront(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CapsLockAsk.matches(transcript) {
            let result = answerCaps(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if FocusRoundsAsk.matches(transcript) {
            let result = answerRounds(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DictationWordsAsk.matches(transcript) {
            let result = answerWords(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if let who = RecordingAsk.who(in: transcript) {
            let result = answerRecording(who, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DarkModeAsk.matches(transcript) {
            let result = answerDarkMode(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if TilingStatusAsk.matches(transcript) {
            let result = answerTiling(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ScreenCountAsk.matches(transcript) {
            let result = answerScreens(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if EarbudsStatusAsk.matches(transcript) {
            let result = answerEarbuds(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if UsageTodayAsk.matches(transcript) {
            let result = answerUsage(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PrompterAsk.matches(transcript) {
            let result = answerScript(transcript, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if LidStatusAsk.matches(transcript) {
            let result = answerLid(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if OutputAsk.matches(transcript) {
            let result = answerOutput(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DictationLiveAsk.matches(transcript) {
            let result = answerDictation(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PolyglotStatusAsk.matches(transcript) {
            let result = answerPolyglot(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ChatCountAsk.matches(transcript) {
            let result = answerChats(transcript, speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HeatAsk.matches(transcript) {
            let result = answerHeat(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HeyZeusAsk.matches(transcript) {
            let result = answerHeyZeus(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if FaceAsk.matches(transcript) {
            let result = answerFace(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if BeamerPlaceAsk.matches(transcript) {
            let result = answerBeamerPlace(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if VoiceChoiceAsk.matches(transcript) {
            let result = answerVoiceChoice(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if LicenseAsk.matches(transcript) {
            let result = answerLicense(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ScreenRecordingAsk.matches(transcript) {
            let result = answerScreenRecording(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DriveAutonomyAsk.matches(transcript) {
            let result = answerDriveAutonomy(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NotchPlaceAsk.matches(transcript) {
            let result = answerNotchPlace(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PointingKeysAsk.matches(transcript) {
            let result = answerPointingKeys(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ChatShortcutAsk.matches(transcript) {
            let result = answerChatShortcut(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ProviderAsk.matches(transcript) {
            let result = answerProvider(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if MusicSourceAsk.matches(transcript) {
            let result = answerMusicSource(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CardStyleAsk.matches(transcript) {
            let result = answerCardStyle(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PointerBuddyAsk.matches(transcript) {
            let result = answerPointerBuddy(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NotchOpenAsk.matches(transcript) {
            let result = answerNotchOpen(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HaloLightAsk.matches(transcript) {
            let result = answerHaloLight(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HomeCardsAsk.matches(transcript) {
            let result = answerHomeCards(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NotchLightsAsk.matches(transcript) {
            let result = answerNotchLights(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if TopBarTabsAsk.matches(transcript) {
            let result = answerTopBarTabs(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CueSoundsAsk.matches(transcript) {
            let result = answerCueSounds(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DictationSetupAsk.matches(transcript) {
            let result = answerDictationSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if VoiceCuesAsk.matches(transcript) {
            let result = answerVoiceCues(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DayToDayAsk.matches(transcript) {
            let result = answerDayToDay(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PrompterSetupAsk.matches(transcript) {
            let result = answerPrompterSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if BrowserAgentAsk.matches(transcript) {
            let result = answerBrowserAgent(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if PolyglotSetupAsk.matches(transcript) {
            let result = answerPolyglotSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if KeepAwakeSetupAsk.matches(transcript) {
            let result = answerKeepAwakeSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if FlingSetupAsk.matches(transcript) {
            let result = answerFlingSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if TilingSetupAsk.matches(transcript) {
            let result = answerTilingSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CodingSetupAsk.matches(transcript) {
            let result = answerCodingSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NotifySetupAsk.matches(transcript) {
            let result = answerNotifySetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ReceiveSetupAsk.matches(transcript) {
            let result = answerReceiveSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if BeamerSetupAsk.matches(transcript) {
            let result = answerBeamerSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if CaptionSetupAsk.matches(transcript) {
            let result = answerCaptionSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if SoundEventsAsk.matches(transcript) {
            let result = answerSoundEvents(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if OtherAppsAsk.matches(transcript) {
            let result = answerOtherApps(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HomeStylesAsk.matches(transcript) {
            let result = answerHomeStyles(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if WeatherPlaceAsk.matches(transcript) {
            let result = answerWeatherPlace(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if InsomniaSetupAsk.matches(transcript) {
            let result = answerInsomniaSetup(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DictationModeAsk.matches(transcript) {
            let result = answerDictationMode(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if VoiceGlowAsk.matches(transcript) {
            let result = answerVoiceGlow(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if DictationRecordAsk.matches(transcript) {
            let result = answerDictationRecord(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if AgentNudgeAsk.matches(transcript) {
            let result = answerAgentNudge(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HomeFrameAsk.matches(transcript) {
            let result = answerHomeFrame(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if ScreenCornerAsk.matches(transcript) {
            let result = answerScreenCorners(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if NotchCloseAsk.matches(transcript) {
            let result = answerNotchClose(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if EverydayLightsAsk.matches(transcript) {
            let result = answerEverydayLights(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if HaloArmAsk.matches(transcript) {
            let result = answerHaloArm(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if MusicLightsAsk.matches(transcript) {
            let result = answerMusicLights(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if RunningCardAsk.matches(transcript) {
            let result = answerRunningCard(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if VoiceStyleAsk.matches(transcript) {
            let result = answerVoiceStyle(speak: speak)
            remember(transcript, result.spoken)
            return result
        }
        if LockChimeAsk.matches(transcript) {
            let result = answerLockChimes(speak: speak)
            remember(transcript, result.spoken)
            return result
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
            if case .add(let items)? = TodoVoice.parse(transcript) {
                let titles = items.map { TodoQuickAdd.parse($0).title }
                if let plan = TodoListDraw.plan(titles: titles) {
                    showTodoList(plan, speak: speak)
                    if speak { say(local) }
                    buddy.showCaption(plan.boltCaption(at: 0))
                    remember(transcript, local)
                    return TurnResult(spoken: local)
                }
            }
            if let kind = TodoVoice.parse(transcript) {
                if case .today = kind, let plan = TodayController.shared.board {
                    return speakToday(plan, local, transcript: transcript, speak: speak)
                }
                if case .brief = kind, let plan = TodayController.shared.board {
                    return speakToday(plan, local, transcript: transcript, speak: speak)
                }
            }
            if let plan = TodoDoneDraw.from(line: local) {
                showTodoDone(plan, speak: speak)
                if speak { say(local) }
                buddy.showCaption(plan.boltCaption(at: 0))
                remember(transcript, local)
                return TurnResult(spoken: local)
            }
            return speakInstant(local, transcript: transcript, speak: speak)
        }
        if let showcase = ExplainShowcase.plan(for: transcript) {
            return presentExplain(showcase, transcript: transcript, speak: speak)
        }
        if let pointed = pointSpokenAsk(transcript, speak: speak) {
            return pointed
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

    /// Draws a project Zeus could not find, under the pointer.
    /// The caller speaks the full line. A project that opens stays on its own card.
    private func showProjectMiss(_ plan: ProjectMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyProjectMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyProjectMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyProjectMiss(_ plan: ProjectMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a start, command, or drive Zeus left alone, under the pointer.
    /// The caller speaks the full line. A spoken approval verdict is not this card.
    private func showLeftAlone(_ plan: LeftAloneDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLeftAlone(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLeftAlone(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLeftAlone(_ plan: LeftAloneDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a calendar that could not take a new event, under the pointer.
    /// The caller speaks the full line. A missing Calendar permission is not this card.
    private func showCalendarFail(_ plan: CalendarFailDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCalendarFail(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCalendarFail(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCalendarFail(_ plan: CalendarFailDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the Calendar grant an event needs, under the pointer.
    /// The caller speaks the full line. An event that was added is not this card.
    private func showCalendarAccess(_ plan: CalendarAccessDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCalendarAccess(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCalendarAccess(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCalendarAccess(_ plan: CalendarAccessDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A browser-agent line. A page that kept changing is drawn; other lines stay spoken.
    func browserSaid(_ text: String) {
        if let visual = PageStaleDraw.from(line: text) {
            showPageStale(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = StepLimitDraw.from(line: text) {
            showStepLimit(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = LoopStopDraw.from(line: text) {
            showLoopStop(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = UnsureStopDraw.from(line: text) {
            showUnsureStop(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = StuckDraw.from(line: text) {
            showStuck(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = SecretFieldDraw.from(line: text) {
            showSecretField(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = NoAIDraw.from(line: text) {
            showNoAI(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = EarlyStopDraw.from(line: text) {
            showEarlyStop(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = NotReadyDraw.from(line: text) {
            showNotReady(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = AgentOffDraw.from(line: text) {
            showAgentOff(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = DeclinedStopDraw.from(line: text) {
            showDeclinedStop(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = BrowserSetupDraw.from(line: text) {
            showBrowserSetup(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = NoGoalDraw.from(line: text) {
            showNoGoal(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = UnusableStepsDraw.from(line: text) {
            showUnusableSteps(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = EndpointMissDraw.from(line: text) {
            showEndpointMiss(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = PageListDraw.from(line: text) {
            showPageList(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = BrowserStoppedDraw.from(line: text) {
            showBrowserStopped(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else {
            say(text)
        }
    }

    /// Draws the separate browser that stopped, under the pointer.
    /// The caller speaks the full line. A page list that could not be read is not this card.
    private func showBrowserStopped(_ plan: BrowserStoppedDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBrowserStopped(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBrowserStopped(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBrowserStopped(_ plan: BrowserStoppedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a separate browser whose page list could not be read, under the pointer.
    /// The caller speaks the full line. A scroll Zeus could not make is not this card.
    private func showPageList(_ plan: PageListDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPageList(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPageList(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPageList(_ plan: PageListDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws an Any LLM endpoint Zeus could not use, under the pointer.
    /// The caller speaks the full line. A browser agent with no AI connected is not this card.
    private func showEndpointMiss(_ plan: EndpointMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyEndpointMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyEndpointMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyEndpointMiss(_ plan: EndpointMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent that kept getting steps it could not use, under the pointer.
    /// The caller speaks the full line. One unread browser step is not this card.
    private func showUnusableSteps(_ plan: UnusableStepsDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyUnusableSteps(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyUnusableSteps(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyUnusableSteps(_ plan: UnusableStepsDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent with nothing to do, under the pointer.
    /// The caller speaks the full line. The separate browser that is not set up is not this card.
    private func showNoGoal(_ plan: NoGoalDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNoGoal(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNoGoal(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNoGoal(_ plan: NoGoalDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the separate browser that is not set up, under the pointer.
    /// The caller speaks the full line. The browser agent turned off is not this card.
    private func showBrowserSetup(_ plan: BrowserSetupDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBrowserSetup(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBrowserSetup(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBrowserSetup(_ plan: BrowserSetupDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser step the person declined, under the pointer.
    /// The caller speaks the full line. A browser agent turned off is not this card.
    private func showDeclinedStop(_ plan: DeclinedStopDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDeclinedStop(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDeclinedStop(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDeclinedStop(_ plan: DeclinedStopDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the browser agent turned off, under the pointer.
    /// The caller speaks the full line. Zeus not ready to drive the browser is not this card.
    private func showAgentOff(_ plan: AgentOffDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgentOff(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgentOff(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgentOff(_ plan: AgentOffDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws Zeus not ready to drive the browser, under the pointer.
    /// The caller speaks the full line. A browser agent with no AI is not this card.
    private func showNotReady(_ plan: NotReadyDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotReady(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotReady(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotReady(_ plan: NotReadyDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent stopped before it started, under the pointer.
    /// The caller speaks the full line. A browser agent with no AI is not this card.
    private func showEarlyStop(_ plan: EarlyStopDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyEarlyStop(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyEarlyStop(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyEarlyStop(_ plan: EarlyStopDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent with no AI connected, under the pointer.
    /// The caller speaks the full line. A spoken answer failure is not this card.
    private func showNoAI(_ plan: NoAIDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNoAI(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNoAI(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNoAI(_ plan: NoAIDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a password or payment field Zeus will not type, under the pointer.
    /// The caller speaks the full line. Typing left undone is not this card.
    private func showSecretField(_ plan: SecretFieldDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySecretField(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySecretField(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySecretField(_ plan: SecretFieldDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The talk shortcut VoiceOver is holding. A pointing hint stays on the notch.
    func keysBlocked(_ text: String) {
        if let visual = VoiceOverDraw.from(line: text) {
            showVoiceOver(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else {
            say(text)
        }
    }

    /// Draws VoiceOver holding the talk keys, under the pointer.
    /// The caller speaks the full line. A saved shortcut is not this card.
    private func showVoiceOver(_ plan: VoiceOverDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVoiceOver(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVoiceOver(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVoiceOver(_ plan: VoiceOverDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A walkthrough line. A finished tour is drawn; step cues stay spoken.
    func walkthroughSaid(_ text: String) {
        if let visual = TourDoneDraw.from(line: text) {
            showTourDone(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = TourStopDraw.from(line: text) {
            showTourStop(visual, speak: true)
            say(text)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else {
            say(text)
        }
    }

    /// Draws a walkthrough the person stopped, under the pointer.
    /// The caller speaks the full line. A finished walkthrough is not this card.
    private func showTourStop(_ plan: TourStopDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTourStop(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTourStop(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTourStop(_ plan: TourStopDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a finished walkthrough, under the pointer.
    /// The caller speaks the full line. A tour Zeus could not put together is not this card.
    private func showTourDone(_ plan: TourDoneDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTourDone(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTourDone(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTourDone(_ plan: TourDoneDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent that is stuck, under the pointer.
    /// The caller speaks the full line. A plan Zeus could not read is not this card.
    private func showStuck(_ plan: StuckDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyStuck(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyStuck(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyStuck(_ plan: StuckDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a drive plan Zeus could not read, under the pointer.
    /// The caller speaks the full line. A drive the person declined is not this card.
    private func showBadPlan(_ plan: BadPlanDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBadPlan(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBadPlan(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBadPlan(_ plan: BadPlanDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent that was not sure enough, under the pointer.
    /// The caller speaks the full line. A loop stop is not this card.
    private func showUnsureStop(_ plan: UnsureStopDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyUnsureStop(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyUnsureStop(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyUnsureStop(_ plan: UnsureStopDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent that was going in circles, under the pointer.
    /// The caller speaks the full line. A step-limit stop is not this card.
    private func showLoopStop(_ plan: LoopStopDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLoopStop(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLoopStop(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLoopStop(_ plan: LoopStopDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser agent that stopped at its step limit, under the pointer.
    /// The caller speaks the full line. A page that kept changing is not this card.
    private func showStepLimit(_ plan: StepLimitDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyStepLimit(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyStepLimit(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyStepLimit(_ plan: StepLimitDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a page that kept changing, under the pointer.
    /// The caller speaks the full line. A step that is already running is not this card.
    private func showPageStale(_ plan: PageStaleDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPageStale(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPageStale(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPageStale(_ plan: PageStaleDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a prompt Zeus did not send, under the pointer.
    /// The caller speaks the full line. Typing left undone is not this card.
    private func showSendSkip(_ plan: SendSkipDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySendSkip(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySendSkip(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySendSkip(_ plan: SendSkipDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws typing Zeus left undone, under the pointer.
    /// The caller speaks the full line. A browser step that could not be read is not this card.
    private func showTypeSkip(_ plan: TypeSkipDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTypeSkip(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTypeSkip(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTypeSkip(_ plan: TypeSkipDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser step Zeus could not read, under the pointer.
    /// The caller speaks the full line. A step that is already running is not this card.
    private func showStepMiss(_ plan: StepMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyStepMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyStepMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyStepMiss(_ plan: StepMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a link that is not a web page, under the pointer.
    /// The caller speaks the full line. Opening a web page is not this card.
    private func showLinkMiss(_ plan: LinkMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLinkMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLinkMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLinkMiss(_ plan: LinkMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a run Zeus could not understand, under the pointer.
    /// The caller speaks the full line. A blocked or declined command is not this card.
    private func showRunUnclear(_ plan: RunUnclearDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRunUnclear(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRunUnclear(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRunUnclear(_ plan: RunUnclearDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a to-do Zeus could not add, under the pointer.
    /// The caller speaks the full line. A to-do that was added is not this card.
    private func showTodoMiss(_ plan: TodoMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTodoMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTodoMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTodoMiss(_ plan: TodoMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a shell command Zeus will not run, under the pointer.
    /// The caller speaks the full line. A command the person declined is not this card.
    private func showShellBlock(_ plan: ShellBlockDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyShellBlock(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyShellBlock(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyShellBlock(_ plan: ShellBlockDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a tour Zeus could not put together, under the pointer.
    /// The caller speaks the full line. A tour that is already walking is not this card.
    private func showTourFail(_ plan: TourFailDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTourFail(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTourFail(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTourFail(_ plan: TourFailDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A model action that failed. Accessibility for Drive is drawn; other lines stay spoken.
    private func sayActionProblem(_ problem: String) {
        let spoken = SpokenFailure.line(problem)
        if let visual = DriveAccessDraw.from(line: problem) ?? DriveAccessDraw.from(line: spoken) {
            showDriveAccess(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = LeftAloneDraw.from(line: spoken) {
            showLeftAlone(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = ProjectMissDraw.from(line: spoken) {
            showProjectMiss(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = TourFailDraw.from(line: spoken) {
            showTourFail(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = ShellBlockDraw.from(line: spoken) {
            showShellBlock(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = RunUnclearDraw.from(line: spoken) {
            showRunUnclear(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = LinkMissDraw.from(line: spoken) {
            showLinkMiss(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = StepMissDraw.from(line: spoken) {
            showStepMiss(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = TypeSkipDraw.from(line: spoken) {
            showTypeSkip(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = SendSkipDraw.from(line: spoken) {
            showSendSkip(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = BadPlanDraw.from(line: spoken) {
            showBadPlan(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = TabOpenDraw.from(line: spoken) {
            showTabOpen(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = ClickLeftDraw.from(line: spoken) {
            showClickLeft(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = PageUntouchedDraw.from(line: spoken) {
            showPageUntouched(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = TabHistoryDraw.from(line: spoken) {
            showTabHistory(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = ScreenStaleDraw.from(line: spoken) {
            showScreenStale(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = ScrollRangeDraw.from(line: spoken) {
            showScrollRange(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = SwitchReadDraw.from(line: spoken) {
            showSwitchRead(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = KeyUnknownDraw.from(line: spoken) {
            showKeyUnknown(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = FindMissDraw.from(line: spoken) {
            showFindMiss(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = FolderMissDraw.from(line: spoken) {
            showFolderMiss(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = WentAwayDraw.from(line: spoken) {
            showWentAway(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if let visual = CantDirectDraw.from(line: spoken) {
            showCantDirect(visual, speak: true)
            say(spoken)
            buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = WindowMissDraw.from(line: spoken) {
                showWindowMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = AskLeftDraw.from(line: spoken) {
                showAskLeft(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = DocumentMissDraw.from(line: spoken) {
                showDocumentMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = PageBlockDraw.from(line: spoken) {
                showPageBlock(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = TabMissDraw.from(line: spoken) {
                showTabMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = AssistantMissDraw.from(line: spoken) {
                showAssistantMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = NoTabDraw.from(line: spoken) {
                showNoTab(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = DocumentGoneDraw.from(line: spoken) {
                showDocumentGone(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = PageTargetDraw.from(line: spoken) {
                showPageTarget(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = NoFieldDraw.from(line: spoken) {
                showNoField(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ClickOffDraw.from(line: spoken) {
                showClickOff(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ClickMissDraw.from(line: spoken) {
                showClickMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ElementMissDraw.from(line: spoken) {
                showElementMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ChoiceMissDraw.from(line: spoken) {
                showChoiceMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = NotFieldDraw.from(line: spoken) {
                showNotField(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = MissingPieceDraw.from(line: spoken) {
                showMissingPiece(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = FieldMissDraw.from(line: spoken) {
                showFieldMiss(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = DriveBusyDraw.from(line: spoken) {
                showDriveBusy(visual, speak: true)
                say(spoken)
                buddy.showCaption(visual.boltCaption(at: 0))
            } else {
                say(spoken)
            }
    }

    /// Draws a window Zeus could not find, under the pointer.
    /// The caller speaks the full line. A control Zeus cannot use directly is not this card.
    private func showWindowMiss(_ plan: WindowMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWindowMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWindowMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWindowMiss(_ plan: WindowMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a start Zeus could not ask about, under the pointer.
    /// The caller speaks the clipped line. A start the person declined is not this card.
    private func showAskLeft(_ plan: AskLeftDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAskLeft(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAskLeft(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAskLeft(_ plan: AskLeftDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws an approved document Zeus could not use, under the pointer.
    /// The caller speaks the full line. A page Zeus left untouched is not this card.
    private func showDocumentMiss(_ plan: DocumentMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDocumentMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDocumentMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDocumentMiss(_ plan: DocumentMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a page Chrome will not let Zeus act on, under the pointer.
    /// The caller speaks the full line. A page Zeus left untouched is not this card.
    private func showPageBlock(_ plan: PageBlockDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPageBlock(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPageBlock(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPageBlock(_ plan: PageBlockDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Chrome tab Zeus could not find, under the pointer.
    /// The caller speaks the full line. A drive target Zeus could not find is not this card.
    private func showTabMiss(_ plan: TabMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTabMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTabMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTabMiss(_ plan: TabMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser assistant Zeus could not find, under the pointer.
    /// The caller speaks the full line. A missing Chrome tab is not this card.
    private func showAssistantMiss(_ plan: AssistantMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAssistantMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAssistantMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAssistantMiss(_ plan: AssistantMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws Chrome with no active tab, under the pointer.
    /// The caller speaks the full line. A Chrome tab Zeus could not find is not this card.
    private func showNoTab(_ plan: NoTabDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNoTab(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNoTab(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNoTab(_ plan: NoTabDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws an approved document that disappeared, under the pointer.
    /// The caller speaks the full line. A document that was never there is not this card.
    private func showDocumentGone(_ plan: DocumentGoneDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDocumentGone(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDocumentGone(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDocumentGone(_ plan: DocumentGoneDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a missing page target, under the pointer.
    /// The caller speaks the full line. A document that disappeared is not this card.
    private func showPageTarget(_ plan: PageTargetDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPageTarget(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPageTarget(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPageTarget(_ plan: PageTargetDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a page with no text field, under the pointer.
    /// The caller speaks the full line. A missing page target is not this card.
    private func showNoField(_ plan: NoFieldDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNoField(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNoField(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNoField(_ plan: NoFieldDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a control Zeus could not click, under the pointer.
    /// The caller speaks the full line. A page with no text field is not this card.
    private func showClickOff(_ plan: ClickOffDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClickOff(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClickOff(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClickOff(_ plan: ClickOffDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a named click Zeus could not find, under the pointer.
    /// The caller speaks the full line. A control that cannot be clicked is not this card.
    private func showClickMiss(_ plan: ClickMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClickMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClickMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClickMiss(_ plan: ClickMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a numbered element Zeus could not find, under the pointer.
    /// The caller speaks the full line. A named click that is not on the page is not this card.
    private func showElementMiss(_ plan: ElementMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyElementMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyElementMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyElementMiss(_ plan: ElementMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a dropdown choice Zeus could not find, under the pointer.
    /// The caller speaks the full line. A numbered element that is not on the page is not this card.
    private func showChoiceMiss(_ plan: ChoiceMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyChoiceMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyChoiceMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyChoiceMiss(_ plan: ChoiceMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a numbered element that is not a text field, under the pointer.
    /// The caller speaks the full line. A page with no text field is not this card.
    private func showNotField(_ plan: NotFieldDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNotField(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNotField(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNotField(_ plan: NotFieldDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a browser action missing a required piece, under the pointer.
    /// The caller speaks the full line. An element that is not a text field is not this card.
    private func showMissingPiece(_ plan: MissingPieceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMissingPiece(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMissingPiece(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMissingPiece(_ plan: MissingPieceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a named field Zeus could not find, under the pointer.
    /// The caller speaks the full line. A page with no text field is not this card.
    private func showFieldMiss(_ plan: FieldMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFieldMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFieldMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFieldMiss(_ plan: FieldMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws that Zeus is already driving, under the pointer.
    /// The caller speaks the full line. Accessibility for Drive is not this card.
    private func showDriveBusy(_ plan: DriveBusyDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDriveBusy(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDriveBusy(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDriveBusy(_ plan: DriveBusyDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a control Zeus cannot use directly, under the pointer.
    /// The caller speaks the full line. A control that went away is not this card.
    private func showCantDirect(_ plan: CantDirectDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyCantDirect(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyCantDirect(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyCantDirect(_ plan: CantDirectDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a control that went away before Zeus could use it, under the pointer.
    /// The caller speaks the full line. A target Zeus could not find is not this card.
    private func showWentAway(_ plan: WentAwayDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWentAway(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWentAway(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWentAway(_ plan: WentAwayDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a folder Zeus could not find, under the pointer.
    /// The caller speaks the full line. A drive target Zeus could not find is not this card.
    private func showFolderMiss(_ plan: FolderMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFolderMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFolderMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFolderMiss(_ plan: FolderMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a drive target Zeus could not find, under the pointer.
    /// The caller speaks the full line. A key Zeus does not know is not this card.
    private func showFindMiss(_ plan: FindMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFindMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFindMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFindMiss(_ plan: FindMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a key combo Zeus does not know, under the pointer.
    /// The caller speaks the full line. A switch Zeus could not read is not this card.
    private func showKeyUnknown(_ plan: KeyUnknownDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyKeyUnknown(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyKeyUnknown(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyKeyUnknown(_ plan: KeyUnknownDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a drive switch Zeus could not read, under the pointer.
    /// The caller speaks the full line. A scroll Zeus could not make is not this card.
    private func showSwitchRead(_ plan: SwitchReadDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySwitchRead(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySwitchRead(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySwitchRead(_ plan: SwitchReadDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a drive scroll Zeus could not make, under the pointer.
    /// The caller speaks the full line. A drive step the screen left behind is not this card.
    private func showScrollRange(_ plan: ScrollRangeDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScrollRange(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScrollRange(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScrollRange(_ plan: ScrollRangeDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a drive step the screen left behind, under the pointer.
    /// The caller speaks the full line. A Chrome page Zeus left untouched is not this card.
    private func showScreenStale(_ plan: ScreenStaleDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScreenStale(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScreenStale(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScreenStale(_ plan: ScreenStaleDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a page Zeus left untouched, under the pointer.
    /// The caller speaks the full line. A page that kept changing is not this card.
    private func showPageUntouched(_ plan: PageUntouchedDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPageUntouched(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPageUntouched(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPageUntouched(_ plan: PageUntouchedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a tab with nowhere to go back or forward, under the pointer.
    /// The caller speaks the full line. A page that kept changing is not this card.
    private func showTabHistory(_ plan: TabHistoryDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTabHistory(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTabHistory(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTabHistory(_ plan: TabHistoryDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a click Zeus left alone, under the pointer.
    /// The caller speaks the full line. A tab Zeus left open is not this card.
    private func showClickLeft(_ plan: ClickLeftDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClickLeft(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClickLeft(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClickLeft(_ plan: ClickLeftDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a tab Zeus left open, under the pointer.
    /// The caller speaks the full line. A prompt Zeus did not send is not this card.
    private func showTabOpen(_ plan: TabOpenDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTabOpen(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTabOpen(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTabOpen(_ plan: TabOpenDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the Accessibility grant Drive mode needs, under the pointer.
    /// The caller speaks the full line. A step that is already running is not this card.
    private func showDriveAccess(_ plan: DriveAccessDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyDriveAccess(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyDriveAccess(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyDriveAccess(_ plan: DriveAccessDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a refused screen lock on the display under the pointer.
    /// The caller speaks the full line. A lock the notch shows is not this card.
    private func showLockFail(_ plan: LockFailDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyLockFail(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyLockFail(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyLockFail(_ plan: LockFailDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a finished timer on the display under the pointer.
    /// The caller speaks the full line. Starting or cancelling stays on its own card.
    private func showTimerFinished(_ plan: TimerFinishedDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTimerFinished(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTimerFinished(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTimerFinished(_ plan: TimerFinishedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the fuller answer on the display under the pointer.
    /// The caller speaks the intro. A blank first sentence is not drawn.
    private func showFullerAnswer(_ plan: FullerAnswerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFullerAnswer(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFullerAnswer(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFullerAnswer(_ plan: FullerAnswerDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a refused volume change on the display under the pointer.
    /// The caller speaks the full line. A change the notch shows is not this card.
    private func showVolumeBlock(_ plan: VolumeBlockDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVolumeBlock(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVolumeBlock(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVolumeBlock(_ plan: VolumeBlockDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Speaks a command-line control refusal and draws Control, then Off.
    private func sayControlOff(_ note: String, speak: Bool) {
        if let visual = ControlOffDraw.from(line: note) {
            showControlOff(visual, speak: speak)
            if speak { say(note) } else { buddy.showCaption(note); buddy.hideCaption() }
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if speak {
            say(note)
        } else {
            buddy.showCaption(note)
            buddy.hideCaption()
        }
    }

    /// Draws command-line control off on the display under the pointer.
    /// The caller speaks the full line.
    private func showControlOff(_ plan: ControlOffDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyControlOff(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyControlOff(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyControlOff(_ plan: ControlOffDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws an action that did not finish, under the pointer.
    /// The caller speaks the full line. An answer failure stays on its own card.
    private func showActionMiss(_ plan: ActionMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyActionMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyActionMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyActionMiss(_ plan: ActionMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the live wait line on the display under the pointer.
    /// The caller speaks the full line. The Play Demo thinking step stays its own script.
    private func showThinking(_ plan: ThinkingDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyThinking(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyThinking(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyThinking(_ plan: ThinkingDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the hearing notice on the display under the pointer.
    /// The caller speaks the full line. A notch permission cue stays on the notch.
    private func showHear(_ plan: HearDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyHear(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyHear(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyHear(_ plan: HearDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a research failure that is a spoken answer failure, under the pointer.
    /// The caller passes the spoken line. A saved report is not this card.
    func showResearchFailure(_ plan: AnswerFailDraw, line: String, speak: Bool) {
        showAnswerFail(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws a research failure that is the missing Claude command-line tool, under the pointer.
    /// The caller passes the spoken line. A spoken answer failure is not this card.
    func showResearchClaudeTool(_ plan: ClaudeToolDraw, line: String, speak: Bool) {
        showClaudeTool(plan, speak: speak)
        if speak { say(line) } else { buddy.showCaption(line); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
    }

    /// Draws a spoken answer failure on the display under the pointer.
    /// The caller speaks the full line. Other sentences are not this card.
    private func showAnswerFail(_ plan: AnswerFailDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAnswerFail(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAnswerFail(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAnswerFail(_ plan: AnswerFailDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the screen-recording notice on the display under the pointer.
    /// The caller speaks the full line. Other sentences are not this card.
    private func showScreenSight(_ plan: ScreenSightDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyScreenSight(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyScreenSight(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyScreenSight(_ plan: ScreenSightDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a named agent's kept note on the display under the pointer.
    /// The caller speaks the full line. A refusal card has no note on it.
    private func showAgentNote(_ plan: AgentNoteDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAgentNote(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAgentNote(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAgentNote(_ plan: AgentNoteDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a stop-all on the display under the pointer while Zeus says it.
    /// The caller speaks the full line. A watch that stops stays on its own card.
    private func showStopAll(_ plan: StopAllDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyStopAll(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyStopAll(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyStopAll(_ plan: StopAllDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the two names Zeus is asking about, under the pointer.
    /// The caller speaks the full question.
    private func showChoice(_ plan: ChoiceDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyChoice(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyChoice(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyChoice(_ plan: ChoiceDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a spoken approval verdict on the display under the pointer.
    /// The caller speaks the full line. The approval prompt stays its own cue.
    private func showApproval(_ plan: ApprovalDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyApproval(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyApproval(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyApproval(_ plan: ApprovalDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// The card for a shortcut Zeus just saved, refused, or replayed.
    private static func shortcutVisual(transcript: String, spoken: String) -> ShortcutDraw? {
        if spoken == "Done." { return ShortcutDraw.done() }
        guard let parsed = NamedShortcutPhrase.parse(transcript) else { return nil }
        if spoken.hasPrefix("Saved ") {
            return ShortcutDraw.saved(phrase: parsed.phrase, steps: parsed.steps)
        }
        return ShortcutDraw.notSaved(phrase: parsed.phrase)
    }

    /// Draws a shortcut on the display under the pointer while Zeus says it.
    /// The caller speaks the full line.
    private func showShortcut(_ plan: ShortcutDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyShortcut(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyShortcut(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyShortcut(_ plan: ShortcutDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a found file on the display under the pointer while Zeus says it is opening.
    /// A miss shows Not found. The caller speaks the full line.
    private func showFileFound(_ plan: FileFoundDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyFileFound(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyFileFound(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyFileFound(_ plan: FileFoundDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Beamer command Zeus could not carry out, under the pointer.
    /// The caller speaks the full line. A Beamer command that ran is not this card.
    private func showBeamerMiss(_ plan: BeamerMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBeamerMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBeamerMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBeamerMiss(_ plan: BeamerMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Beamer command on the display under the pointer while it runs.
    /// The caller speaks the full line. Switching to an app stays on the app card.
    private func showBeamer(_ plan: BeamerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyBeamer(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyBeamer(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyBeamer(_ plan: BeamerDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Spotify request on the display under the pointer while it starts.
    /// The caller speaks the full line. A media key stays on the media card.
    private func showSpotify(_ plan: SpotifyPlayDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySpotify(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySpotify(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySpotify(_ plan: SpotifyPlayDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a terminal on the display under the pointer while it opens.
    /// The caller speaks the full line. A named project appears on the next beat.
    private func showTerminal(_ plan: TerminalOpenDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTerminal(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTerminal(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTerminal(_ plan: TerminalOpenDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws quit, hide, or a missing app on the display under the pointer.
    /// The caller speaks the full line.
    private func showAppClose(_ plan: AppCloseDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAppClose(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAppClose(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAppClose(_ plan: AppCloseDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws the research question on the display under the pointer while the search starts.
    /// The finished answer still draws its sites later. The caller speaks the full line.
    private func showResearchStart(_ plan: ResearchStartDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyResearchStart(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyResearchStart(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyResearchStart(_ plan: ResearchStartDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a media key on the display under the pointer: Media, then the action.
    /// The caller speaks the full line.
    private func showMedia(_ plan: MediaDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMedia(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMedia(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMedia(_ plan: MediaDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws an app open or switch on the display under the pointer. The caller speaks the full line.
    /// A site summary is left for the site card.
    private func showAppLaunch(_ plan: AppLaunchDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyAppLaunch(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyAppLaunch(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyAppLaunch(_ plan: AppLaunchDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws live translation starting or stopping. The caller speaks the full line.
    private func showTranslation(_ plan: TranslationDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTranslation(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTranslation(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTranslation(_ plan: TranslationDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a site open on the display under the pointer: Site, then the host.
    /// The caller speaks the full line. A mail link or a file is not drawn.
    private func showSiteOpen(_ plan: SiteOpenDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySiteOpen(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySiteOpen(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySiteOpen(_ plan: SiteOpenDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    private static func projectAppTitle(_ app: FastIntent.ProjectApp) -> String {
        switch app {
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .xcode: "Xcode"
        case .finder: "Finder"
        case .terminal: "Terminal"
        }
    }

    /// Draws a project open on the display under the pointer: Open, then the project, then the app.
    /// The caller speaks the full line.
    private func showProjectOpen(_ plan: ProjectOpenDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyProjectOpen(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyProjectOpen(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyProjectOpen(_ plan: ProjectOpenDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a timer on the display under the pointer. The caller speaks the full line.
    /// Cancelling shows only Cancelled.
    private func showTimer(_ plan: TimerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyTimer(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyTimer(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyTimer(_ plan: TimerDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws live translation that is turned off in Settings, under the pointer.
    /// The caller speaks the full line. Starting or stopping translation is not this card.
    private func showPolyglotOff(_ plan: PolyglotOffDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPolyglotOff(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPolyglotOff(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPolyglotOff(_ plan: PolyglotOffDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Spotify request Zeus could not press play on, under the pointer.
    /// The caller speaks the full line. A Spotify request that is starting is not this card.
    private func showSpotifyPress(_ plan: SpotifyPressDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flySpotifyPress(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flySpotifyPress(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flySpotifyPress(_ plan: SpotifyPressDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a Beamer menu item that did not respond, under the pointer.
    /// The caller speaks the full line. A Beamer command that did not answer is not this card.
    private func showMenuMiss(_ plan: MenuMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMenuMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMenuMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMenuMiss(_ plan: MenuMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws that no timer is running, under the pointer.
    /// The caller speaks the full line. A timer that finishes is not this card.
    private func showNoTimer(_ plan: NoTimerDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyNoTimer(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyNoTimer(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyNoTimer(_ plan: NoTimerDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws that Zeus is already researching, under the pointer.
    /// The caller speaks the full line. A research question is not this card.
    private func showResearchBusy(_ plan: ResearchBusyDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyResearchBusy(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyResearchBusy(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyResearchBusy(_ plan: ResearchBusyDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
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
                if case .addEvent(let text) = plan.intent,
                   let parsed = CalendarQuickAdd.parse(text), parsed.hadDate,
                   let visual = CalendarEventDraw.plan(title: parsed.title, when: Self.eventWhen(parsed)) {
                    self.showCalendarEvent(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .addTodos(let items) = plan.intent,
                          let visual = TodoListDraw.plan(titles: items.map { TodoQuickAdd.parse($0).title }) {
                    self.showTodoList(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .codeAgent(let tool, let project, let task) = plan.intent,
                          let visual = AgentStartDraw.plan(tool: (tool ?? CodingTool.preferred()).title,
                                                           project: project, task: task) {
                    self.showAgentStart(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .timer(let seconds) = plan.intent, let visual = TimerDraw.plan(seconds: seconds) {
                    self.showTimer(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .openProject(let name, let app) = plan.intent,
                          let visual = ProjectOpenDraw.plan(name: name, app: Self.projectAppTitle(app)) {
                    self.showProjectOpen(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .openURL(let url) = plan.intent, let visual = SiteOpenDraw.plan(url: url.absoluteString) {
                    self.showSiteOpen(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .polyglot(let start) = plan.intent {
                    let visual = TranslationDraw.plan(starting: start)
                    self.showTranslation(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .openApp = plan.intent, let visual = AppLaunchDraw.from(summary: plan.summary) {
                    self.showAppLaunch(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .media(let command) = plan.intent, let visual = MediaDraw.plan(action: command.rawValue) {
                    self.showMedia(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .research(let topic, let deep) = plan.intent,
                          !ResearchRunner.shared.isRunning,
                          let visual = ResearchStartDraw.plan(topic: topic, deep: deep) {
                    self.showResearchStart(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if let visual = AppCloseDraw.from(summary: plan.summary) {
                    self.showAppClose(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .openTerminal = plan.intent, let visual = TerminalOpenDraw.from(summary: plan.summary) {
                    self.showTerminal(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .playOnSpotify = plan.intent, let visual = SpotifyPlayDraw.from(summary: plan.summary) {
                    self.showSpotify(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if case .beamer = plan.intent, let visual = BeamerDraw.from(summary: plan.summary) {
                    self.showBeamer(visual, speak: speak)
                    if speak { self.say(ack) } else { self.buddy.showCaption(ack); self.buddy.hideCaption() }
                    self.buddy.showCaption(visual.boltCaption(at: 0))
                } else if speak {
                    self.say(ack)
                } else {
                    self.buddy.showCaption(ack)
                    self.buddy.hideCaption()
                }
            }
        }
        fast.signposter.endInterval("fast action", interval)
        // QA7 round 10: `plan.ack == nil` means "says nothing, the notch cue is enough" (see
        // `AckLines.rawNeutral`'s `.media`/`.volume`/`.locking` cases) -- `say()` is correctly
        // never called for those below, but this field used to fall back to `plan.summary`
        // ("Play", a bare verb) and report it as if it had been spoken. Report what was actually
        // said, which is nothing.
        var result = TurnResult(spoken: plan.ack ?? "", actions: ["fast \(plan.intent.intentLabel) via \(engine): \(plan.summary)"])
        if problem == nil, case .cancelTimer = plan.intent {
            let visual = TimerDraw.cancelled()
            showTimer(visual, speak: speak)
            buddy.showCaption(visual.boltCaption(at: 0))
        }
        if let problem {
            result.problems.append(problem)
            AvatarStatus.shared.flash(.error, for: 2)
            VoiceLog.logContent("error", problem, prefix: "action problem: ")
            ZeusSound.play(.voiceError)
            let spoken = SpokenFailure.line(problem)
            if let visual = ActionMissDraw.from(line: spoken) {
                showActionMiss(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = VolumeBlockDraw.from(line: spoken) {
                showVolumeBlock(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = LockFailDraw.from(line: spoken) {
                showLockFail(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = CalendarAccessDraw.from(line: spoken) {
                showCalendarAccess(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = CalendarFailDraw.from(line: spoken) {
                showCalendarFail(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ProjectMissDraw.from(line: spoken) {
                showProjectMiss(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = TodoMissDraw.from(line: spoken) {
                showTodoMiss(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = BeamerMissDraw.from(line: spoken) {
                showBeamerMiss(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = PolyglotOffDraw.from(line: spoken) {
                showPolyglotOff(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = SpotifyPressDraw.from(line: spoken) {
                showSpotifyPress(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = MenuMissDraw.from(line: spoken) {
                showMenuMiss(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = NoTimerDraw.from(line: spoken) {
                showNoTimer(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ResearchBusyDraw.from(line: spoken) {
                showResearchBusy(visual, speak: speak)
                if speak { say(spoken) } else { buddy.showCaption(spoken); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if speak {
                say(spoken)
            } else {
                buddy.showCaption(spoken)
                buddy.hideCaption()
            }
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
        sayControlOff(note, speak: speak)
        var result = TurnResult(spoken: note)
        result.problems.append(note)
        return result
    }

    /// Not sure which one you meant: ask instead of guessing.
    private func askBack(_ question: String, engine: String, transcript: String, speak: Bool) -> TurnResult {
        VoiceLog.logContent("route", question, prefix: "fast via \(engine) asks: ")
        buddy.idle()
        if let visual = ChoiceDraw.from(question: question) {
            showChoice(visual, speak: speak)
            if speak { say(question) } else { buddy.showCaption(question); buddy.hideCaption() }
            buddy.showCaption(visual.boltCaption(at: 0))
        } else if speak {
            say(question)
        } else {
            buddy.showCaption(question)
            buddy.hideCaption()
        }
        remember(transcript, question)
        return TurnResult(spoken: question)
    }

    /// Speaks the explanation and draws it on the display under the pointer.
    /// Beat 0 is shown immediately. A moving ask grows the pen. A still ask draws the box one
    /// side at a time during the first sentence, then the arrow, then the card. Later beats
    /// follow `ExplainBeatSchedule` even when no voice engine starts, so the sequence is not
    /// spoken-only and not painted all at once. No capture and no model request.
    /// `talk.drawOnScreen` still gates a screenshot sent to an engine. This path does not send one.
    private func presentExplain(_ plan: ExplainShowcase, transcript: String, speak: Bool) -> TurnResult {
        VoiceLog.log("route", "explain-showcase")
        VoiceLog.log("brain", "engine=local model=none first_token_ms=0 done_ms=0")
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = plan.scaled(toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        let surface = presenter
        let ready = surface.begin(draw, shot: shot, token: token)
        drawActive = ready
        explainBegan = Date()
        VoiceLog.log("draw", "explain marks=\(draw.marks.count) pen=\(plan.stroke.count) display=\(Int(shot.displayFrame.width))x\(Int(shot.displayFrame.height))")
        // Leave listening before the pen flies. idle() clears a flight, so it has to run first.
        buddy.idle()
        if plan.travels, ready {
            showPen(plan.penFrame(at: 0), shot: shot, token: token, label: plan.boltCaption(at: 0))
            explainReveal = Task { @MainActor [weak self] in
                var shown = 0
                while !Task.isCancelled {
                    guard let self else { return }
                    let elapsed = Date().timeIntervalSince(self.explainBegan)
                    guard let frame = plan.penFrame(at: elapsed, audioStarts: self.explainAudioStarts) else { return }
                    if frame.pointCount != shown {
                        shown = frame.pointCount
                        self.showPen(frame, shot: shot, token: token, label: plan.boltCaption(at: elapsed))
                    }
                    if frame.finished { break }
                    try? await Task.sleep(for: .milliseconds(40))
                }
                guard let self, !Task.isCancelled else { return }
                await self.finishExplainDrawing(token: token, speak: speak)
            }
        } else if ready, plan.builtFrame(at: 0) != nil {
            showBuilt(plan.builtFrame(at: 0), shot: shot, token: token)
            flyGuide(plan, at: 0, shot: shot, label: plan.boltCaption(at: 0))
            explainReveal = Task { @MainActor [weak self] in
                var ink = plan.builtInkCount(at: 0)
                var beats = plan.schedule.revealed(at: 0).count
                while !Task.isCancelled {
                    guard let self else { return }
                    let elapsed = Date().timeIntervalSince(self.explainBegan)
                    let shownBeats = plan.schedule.revealed(at: elapsed).count
                    let count = plan.builtInkCount(at: elapsed)
                    if count != ink || shownBeats != beats {
                        let beatChanged = shownBeats != beats
                        ink = count
                        beats = shownBeats
                        self.showBuilt(plan.builtFrame(at: elapsed), shot: shot, token: token)
                        if beatChanged {
                            self.flyGuide(plan, at: elapsed, shot: shot, label: plan.boltCaption(at: elapsed))
                        }
                    }
                    if shownBeats >= plan.schedule.indexes.count { break }
                    try? await Task.sleep(for: .milliseconds(40))
                }
                guard let self, !Task.isCancelled else { return }
                await self.finishExplainDrawing(token: token, speak: speak)
            }
        } else if ready {
            let beats = plan.schedule.indexes
            if let first = beats.first { surface.reveal(sentence: first, token: token) }
            flyGuide(plan, at: 0, shot: shot, label: plan.boltCaption(at: 0))
            explainReveal = Task { @MainActor [weak self] in
                for (offset, beat) in beats.dropFirst().enumerated() {
                    try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                    guard !Task.isCancelled else { return }
                    let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                    self?.presenter.reveal(sentence: beat, token: token)
                    self?.flyGuide(plan, at: elapsed, shot: shot, label: plan.boltCaption(at: elapsed))
                }
                guard let self, !Task.isCancelled else { return }
                await self.finishExplainDrawing(token: token, speak: speak)
            }
        }
        if speak {
            for (index, sentence) in plan.sentences.enumerated() {
                speaker.speak(Self.voiced(sentence), onStart: { [weak self] in
                    guard let self, index < self.explainAudioStarts.count else { return }
                    self.explainAudioStarts[index] = Date().timeIntervalSince(self.explainBegan)
                })
            }
        }
        let spoken = plan.explanation
        buddy.showCaption(Self.captionTail(spoken))
        buddy.hideCaption()
        remember(transcript, spoken)
        ZeusSound.play(.voiceDone)
        return TurnResult(spoken: spoken)
    }

    /// The marks stay up through the last spoken sentence, then the presenter keeps them a few seconds.
    private func finishExplainDrawing(token: UUID, speak: Bool) async {
        if speak {
            while speaker.isSpeaking {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        presenter.answerFinished(token: token)
    }

    private func flyGuide(_ plan: ExplainShowcase, at elapsed: TimeInterval, shot: ScreenShot, label: String) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: label)
    }

    private func showBuilt(_ draw: TalkDraw?, shot: ScreenShot, token: UUID) {
        guard let draw else { return }
        let scaled = ExplainShowcase.scaled(draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        guard presenter.showFrame(scaled, token: token) else {
            if presenter.penShouldStop(token) {
                buddy.idle()
                explainReveal?.cancel()
            }
            return
        }
    }

    private func showPen(_ frame: ExplainPenFrame?, shot: ScreenShot, token: UUID, label: String) {
        guard let frame else { return }
        let scaled = ExplainShowcase.scaled(frame.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        guard presenter.showFrame(scaled, token: token) else {
            if presenter.penShouldStop(token) {
                buddy.idle()
                explainReveal?.cancel()
            }
            return
        }
        let bolt = boltScreen(frame.bolt, shot: shot)
        buddy.flight(to: bolt, label: label)
    }

    /// Canvas point to AppKit global point on the shot's display. Y flips to the bottom-left origin.
    private func boltScreen(_ point: TalkDraw.Point, shot: ScreenShot) -> CGPoint {
        let px = point.x * Double(shot.pixelWidth) / ExplainShowcase.canvasWidth
        let py = point.y * Double(shot.pixelHeight) / ExplainShowcase.canvasHeight
        let scaleX = max(Double(shot.pixelWidth) / Double(shot.displayFrame.width), 0.001)
        let scaleY = max(Double(shot.pixelHeight) / Double(shot.displayFrame.height), 0.001)
        return CGPoint(x: shot.displayFrame.minX + px / scaleX, y: shot.displayFrame.maxY - py / scaleY)
    }

    /// The display under the pointer, else the main display. The frame is the one
    /// `TalkVisualPresenter` matches, so the marks land on that screen. JPEG bytes stay empty.
    private func illustrationShot() -> ScreenShot {
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        let chosen = screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? screens.first
        let frame = chosen?.frame ?? CGRect(x: 0, y: 0, width: CGFloat(ExplainShowcase.canvasWidth), height: CGFloat(ExplainShowcase.canvasHeight))
        let scale = Double(chosen?.backingScaleFactor ?? 1)
        let pixels = VisualFlight.pixelSize(width: Double(frame.width), height: Double(frame.height), scale: scale)
        return ScreenShot(jpegData: Data(), label: "illustration canvas", pixelWidth: pixels.width, pixelHeight: pixels.height, displayFrame: frame)
    }

    private func remember(_ user: String, _ assistant: String) {
        history.append(Exchange(user: user, assistant: assistant))
        if history.count > 10 { history.removeFirst(history.count - 10) }
    }

    /// Draws a vault lookup that found no notes, under the pointer.
    /// The caller speaks the full line. A note that was found is not this card.
    private func showVaultMiss(_ plan: VaultMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyVaultMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyVaultMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyVaultMiss(_ plan: VaultMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    private func handleSecondBrain(_ transcript: String, speak: Bool) -> TurnResult? {
        guard let topic = BrainRecall.topic(from: transcript), let vault = connectedBrainVault(),
              SecondBrain.looksLikeVault(vault) else { return nil }
        let answer = BrainRecall.spokenAnswer(vault: vault, topic: topic)
        VoiceLog.log("route", "second-brain")
        if let plan = VaultMissDraw.from(line: answer) {
            buddy.idle()
            showVaultMiss(plan, speak: speak)
            if speak { say(answer) }
            buddy.showCaption(plan.boltCaption(at: 0))
            remember(transcript, answer)
            return TurnResult(spoken: answer)
        }
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
        var shown: MemoryKeptDraw?
        var pendingFact: String?
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
                    pendingFact = text
                case .rejectedSensitive:
                    reply = "I can't store sensitive things like that."
                    shown = MemoryKeptDraw.refused()
                case .rejectedScreenSource:
                    reply = "I only remember what you tell me, not what's on screen."
                    shown = MemoryKeptDraw.refused()
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
                    pendingFact = nil
                    shown = nil
                    logOutcome = "save failed"
                }
            }
        } catch {
            VoiceLog.logContent("error", error.localizedDescription, prefix: "memory load: ")
            reply = "I can't read my memory file, so I left it alone."
            logOutcome = "load failed"
        }
        VoiceLog.log("memory", logOutcome)
        if let pendingFact, let kept = MemoryKeptDraw.plan(fact: pendingFact) { shown = kept }
        buddy.idle()
        if let unchanged = MemoryUnchangedDraw.from(line: reply) {
            showMemoryUnchanged(unchanged, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(unchanged.boltCaption(at: 0))
        } else if let unread = MemoryUnreadDraw.from(line: reply) {
            showMemoryUnread(unread, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(unread.boltCaption(at: 0))
        } else if let ask = ForgetAskDraw.from(line: reply) {
            showForgetAsk(ask, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(ask.boltCaption(at: 0))
        } else if let missed = ForgetMissDraw.from(line: reply) {
            showForgetMiss(missed, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(missed.boltCaption(at: 0))
        } else if let forgot = ForgotDraw.from(line: reply) {
            showForgot(forgot, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(forgot.boltCaption(at: 0))
        } else {
            if let shown { showMemoryKept(shown, speak: speak) }
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            if let shown { buddy.showCaption(shown.boltCaption(at: 0)) }
        }
        remember(transcript, reply)
        return TurnResult(spoken: reply)
    }

    /// Draws a memory Zeus could not find, under the pointer.
    /// The caller speaks the full line. Asking which one to forget is not this card.
    private func showForgetMiss(_ plan: ForgetMissDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyForgetMiss(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyForgetMiss(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyForgetMiss(_ plan: ForgetMissDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws one memory Zeus forgot, under the pointer.
    /// The caller speaks the full line. A memory Zeus could not find is not this card.
    private func showForgot(_ plan: ForgotDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyForgot(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyForgot(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyForgot(_ plan: ForgotDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws Zeus asking which memory to forget, under the pointer.
    /// The caller speaks the full line. A memory that was not found is not this card.
    private func showForgetAsk(_ plan: ForgetAskDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyForgetAsk(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyForgetAsk(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyForgetAsk(_ plan: ForgetAskDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a memory file Zeus could not read, under the pointer.
    /// The caller speaks the full line. A memory that could not be saved is not this card.
    private func showMemoryUnread(_ plan: MemoryUnreadDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMemoryUnread(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMemoryUnread(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMemoryUnread(_ plan: MemoryUnreadDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a memory Zeus could not save, under the pointer.
    /// The caller speaks the full line. A fact that was kept is not this card.
    private func showMemoryUnchanged(_ plan: MemoryUnchangedDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMemoryUnchanged(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMemoryUnchanged(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMemoryUnchanged(_ plan: MemoryUnchangedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// Draws a kept memory, or the refusal, on the display under the pointer.
    /// The caller speaks the full line. A refusal card has no fact on it.
    private func showMemoryKept(_ plan: MemoryKeptDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyMemoryKept(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyMemoryKept(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyMemoryKept(_ plan: MemoryKeptDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    private static func watchWait(_ watch: ZeusWatch) -> String {
        switch watch.trigger {
        case .shellTest: "Build finishes"
        case .windowShows: "Appears"
        case .windowGone: "Goes away"
        }
    }

    /// Draws a watch on the display under the pointer. The caller speaks the full line.
    /// Stopping names no target. The shell test stays off the card.
    private func showWatch(_ plan: WatchDraw, reply: String, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else {
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            return
        }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyWatch(plan, at: 0, shot: shot)
        if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
        buddy.showCaption(plan.boltCaption(at: 0))
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyWatch(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyWatch(_ plan: WatchDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    private func handleWatch(_ transcript: String, speak: Bool) -> TurnResult? {
        if transcript.lowercased().contains("stop watching") {
            ZeusWatchRunner.shared.stopAll()
            let reply = "Stopped watching."
            buddy.idle()
            showWatch(WatchDraw.stopped(), reply: reply, speak: speak)
            return TurnResult(spoken: reply)
        }
        guard let watch = ZeusWatchVoice.parse(transcript) else { return nil }
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        ZeusWatchRunner.shared.startWatch(watch)
        let reply = "I'll watch for that."
        buddy.idle()
        if let plan = WatchDraw.plan(label: watch.label, waiting: Self.watchWait(watch)) {
            showWatch(plan, reply: reply, speak: speak)
        } else if speak {
            say(reply)
        } else {
            buddy.showCaption(reply)
            buddy.hideCaption()
        }
        return TurnResult(spoken: reply)
    }

    /// Draws a saved routine on the display under the pointer: Routine, then the name, then when it runs.
    /// The caller speaks the full line. The marks still appear when that speech is off.
    private func showRoutineSaved(_ plan: RoutineSavedDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyRoutineSaved(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyRoutineSaved(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyRoutineSaved(_ plan: RoutineSavedDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    private func handleRoutineVoice(_ transcript: String, speak: Bool) -> TurnResult? {
        guard let parsed = RoutineVoiceParse.parse(transcript) else { return nil }
        if CLIAccess.turnRestricted { return refuseRestricted(speak: speak) }
        let routine = Routine(name: parsed.name, prompt: parsed.prompt, schedule: parsed.schedule, engine: Routine.voiceDefaultEngine)
        RoutineRunner.shared.add(routine)
        let reply = "Routine saved."
        buddy.idle()
        let when = RoutineSavedDraw.whenLine(daily: parsed.schedule.days == .daily, hour: parsed.schedule.hour)
        if let plan = RoutineSavedDraw.plan(name: parsed.name, when: when) {
            showRoutineSaved(plan, speak: speak)
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            buddy.showCaption(plan.boltCaption(at: 0))
        } else if speak {
            say(reply)
        } else {
            buddy.showCaption(reply)
            buddy.hideCaption()
        }
        return TurnResult(spoken: reply)
    }

    private func runTurn(transcript: String, screenshots: [ScreenShot], activeTab: TabContext?, turn: UUID,
                         deep: Bool, speak: Bool, awaitActions: Bool,
                         replay: (id: String, events: AsyncThrowingStream<BrainEvent, Error>)? = nil,
                         pageText: Bool = false,
                         // The speculative run behind `replay` was started before the screenshots and the draw prompt
                         // were in hand, so its answer never draws (its coordinates would mean nothing).
                         replaySawScreen: Bool = false) async -> TurnResult {
        // Named agents: "ask Scout to ...", "Scribe, ...". Each has its own persona and memory.
        let agentStore = AgentStore()
        let route = AgentRouter.route(transcript, agents: agentStore.profiles())
        if let route, let note = route.remember {
            if AgentNoteDraw.hides(note) {
                let reply = "I can't store that."
                buddy.idle()
                if let visual = AgentNoteDraw.refused(agent: route.agent.name) {
                    showAgentNote(visual, speak: speak)
                    if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
                    buddy.showCaption(visual.boltCaption(at: 0))
                } else if speak {
                    say(reply)
                } else {
                    buddy.showCaption(reply)
                    buddy.hideCaption()
                }
                return TurnResult(spoken: reply)
            }
            var memory = agentStore.memory(for: route.agent)
            memory.remember(note, pinned: true)
            try? agentStore.save(memory, for: route.agent)
            let reply = "\(route.agent.name) will remember that."
            NSLog("[ZEUS] agent %@: pinned note (%d notes)", route.agent.name, memory.notes.count)
            buddy.idle()
            if let visual = AgentNoteDraw.plan(agent: route.agent.name, note: note) {
                showAgentNote(visual, speak: speak)
                if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if speak {
                say(reply)
            } else {
                buddy.showCaption(reply)
                buddy.hideCaption()
            }
            return TurnResult(spoken: reply)
        }
        VoiceLog.log("route", "brain (LLM)\(route.map { ", agent \($0.agent.name)" } ?? "")")
        // No network or process work before the engines start: the Ollama check runs at key press and the
        // launch warm-up never blocks a turn (both used to wait here, ahead of the first token).
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
        // Seeing the screen sends one image per display to the image-capable provider and keeps pixels even when window
        // text exists. Drawing marks is a separate consent: it cuts the request to the cursor display.
        let seeScreen = seeScreenConsent(), drawConsented = drawConsent()
        let sight = TalkSightPolicy.plan(
            seeScreen: seeScreen, drawConsent: drawConsented, restricted: restricted, pageRoute: pageText,
            textAnswersIt: awareness.preferPixels == false && !awareness.promptPrefix.isEmpty, captured: shots)
        shots = sight.kept
        let drawing = sight.drawing
        if drawing {
            system += "\n\n" + ZeusPrompt.drawInstructions()
        }
        // Only the brain request is cut to one display; POINT screenN tags and the drive and walkthrough actions keep every capture.
        let requestShots = sight.request
        var screenReason: ScreenSightReason?
        var owesSightNotice = false
        if requestShots.isEmpty {
            if shots.isEmpty {
                let granted = screenPermission()
                screenReason = granted ? .notCaptured : .permissionOff
                owesSightNotice = !granted && !restricted && !pageText && (seeScreen || drawConsented)
            } else {
                screenReason = .turnedOff // captured for POINT and drive, but seeing and drawing are both off
            }
        }
        let drawToken = UUID()
        if let route {
            system += "\n\n" + AgentRouter.preamble(route.agent, memory: agentStore.memory(for: route.agent))
            NSLog("[ZEUS] agent %@: routed turn", route.agent.name)
        }
        var result = TurnResult()
        let request = BrainRequest(
            turn: turn,
            transcript: route?.request ?? transcript,
            screenshots: requestShots,
            axSummary: includeFront ? Self.context(controls: activeTab == nil && !restricted) : nil,
            activeTab: activeTab,
            history: history,
            systemPrompt: system,
            deep: deep,
            carriesDrawImage: sight.sendsImages,
            screenReason: screenReason
        )
        turnObserver?(TurnObservation(request: request, preferAppClaude: sight.sendsImages, shots: shots))

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
        let releasedAt = turnReleasedAt ?? .now
        turnReleasedAt = nil
        var timingFirstToken: Int?
        func msSinceRelease() -> Int {
            let d = ContinuousClock.now - releasedAt
            return max(0, Int(d.components.seconds) * 1000 + Int(d.components.attoseconds / 1_000_000_000_000_000))
        }
        let personaSentenceLimit = PersonaReplyClamp.maxSentences(transcript: transcript, personality: ZeusPersonality.current())
        var spokenSentenceCount = 0
        var haltedForPersonaLimit = false
        var blockedByRestriction = false
        var winnerID: String?
        var drawBegun = false
        var actionStarted = false
        var fillerGate = TurnFillerGate()

        func handle(_ output: ZeusTagStreamParser.Output) {
            switch output {
            case .tag(.point(let target?)):
                if let point = globalPoint(x: target.x, y: target.y, screen: target.screen, in: shots) {
                    buddy.point(to: point, label: Self.pointLabel(target.label, fallback: "right here"))
                    pointed = true
                }
            case .tag(.highlight(let area)):
                if let ring = PresentPointMapping.screenRect(x: area.x, y: area.y, width: area.width, height: area.height,
                                                             screen: area.screen, in: shots) {
                    buddy.point(to: CGPoint(x: ring.midX, y: ring.midY),
                                label: Self.pointLabel(area.label, fallback: "this area"), ring: ring)
                    pointed = true
                }
            case .tag(.action(let action)):
                actionStarted = true
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
                        let outcome = await CodeActions.shared.perform(command, speak: speak, fromModel: true)
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
                    let beats = PresentCard.parse(action.payload)?.beats() ?? []
                    if !beats.isEmpty { pointed = true }
                    task = Task { @MainActor in
                        guard !beats.isEmpty else { return nil }
                        if let plan = PresentStepsDraw.plan(lines: beats.map(\.bolt)) {
                            self.showPresentSteps(plan, spoken: beats.map(\.spoken), speak: speak)
                            return nil
                        }
                        let first = beats[0]
                        let anchor = NSEvent.mouseLocation
                        let ring = CGRect(x: anchor.x - 28, y: anchor.y - 18, width: 56, height: 36)
                        self.buddy.point(to: anchor, label: first.bolt, ring: ring)
                        if speak {
                            for beat in beats {
                                self.speaker.speak(Self.voiced(beat.spoken), onStart: { [weak self] in
                                    self?.buddy.showCaption(beat.bolt)
                                })
                            }
                        }
                        return nil
                    }
                default:
                    task = Task { [chrome] in await chrome.perform(action) }
                }
                actionTasks.append(task)
                if !awaitActions {
                    Task { [weak self] in
                        if let problem = await task.value { self?.sayActionProblem(problem) }
                    }
                }
            case .tag(.point(nil)):
                break
            case .tag(.draw(let draw)):
                guard drawing, !drawBegun, let shot = shots.first,
                      TalkSightPolicy.drawAllowed(winner: winnerID, request: request,
                                                  supportsNoSessionPersistence: supportsNoSessionPersistence(),
                                                  drawInstructions: ZeusPrompt.drawInstructions()) else { break }
                drawBegun = true
                drawActive = presenter.begin(draw, shot: shot, token: drawToken)
                VoiceLog.log("draw", "marks=\(draw.marks.count)")
                // Sentences already handed out will not get another start. Show their marks now.
                for index in TalkDrawReveal.catchUp(spokenSentences: spokenSentenceCount) {
                    presenter.reveal(sentence: index, token: drawToken)
                }
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
                    if spokenSentenceCount == 1 {
                        VoiceLatency.shared.mark(.firstSentence)
                        VoiceLog.log("timing", "release->firstToken ms=\(timingFirstToken ?? -1), ->firstSentence ms=\(msSinceRelease()) (audio starts speech_start_ms later, see speaker line)")
                    }
                    if speak {
                        let index = spokenSentenceCount - 1
                        let reveal = revealCallback(index, token: drawToken)
                        speaker.speak(Self.voiced(sentence), onStart: reveal)
                    } else if let index = TalkDrawReveal.sentenceReady(index: spokenSentenceCount - 1, speak: false, drawingReady: drawBegun) {
                        presenter.reveal(sentence: index, token: drawToken)
                    }
                    buddy.showCaption(Self.captionTail(spoken))
                }
            }
        }

        do {
            let started = Date()
            var replayed = false
            if let replay {
                VoiceLog.log("route", "brain speculative \(replay.id)")
                winnerID = replaySawScreen ? replay.id : nil
                do {
                    VoiceLatency.shared.mark(.requestSent)
                    try await Self.consume(replay.events, engine: { replay.id }, started: started) { delta in
                        if timingFirstToken == nil {
                            timingFirstToken = msSinceRelease()
                            VoiceLatency.shared.setBrain(engine: replay.id, model: Self.modelLabel(replay.id))
                            VoiceLatency.shared.mark(.firstToken)
                        }
                        parser.feed(delta).forEach(handle)
                    }
                    replayed = true
                } catch where spoken.isEmpty && !Task.isCancelled {
                    // The speculative run failed before saying anything: answer from a fresh race instead.
                    VoiceLog.logContent("route", error.localizedDescription, prefix: "speculative \(replay.id) failed; racing; detail ")
                }
            }
            if !replayed {
                // The task's privacy rule and provider choice decide the candidates before any
                // provider (and so any request) is created; a private task never sees a cloud engine.
                let taskKind = RouterTask.classify(transcript)
                let candidates = engineCandidatesOverride?() ?? RouterSettings.shared.brainEngineCandidates(
                    task: taskKind, hasAnthropicKey: AnthropicAPIProvider.hasKey, claude: brain, preferAppClaude: sight.sendsImages)
                let ordered = BrainLatencyBook.shared.ordered(candidates, id: \.id)
                guard !ordered.isEmpty else {
                    VoiceLog.log("route", "brain (none)")
                    throw ClaudeCLIProvider.ProviderError.failed(
                        taskKind == .privateLocal ? "no local AI is available for a private request" : "no AI answered")
                }
                // Every fast engine starts at once; the first to stream text speaks and the rest stop.
                let engines = ordered.map(\.engine)
                let fastSet = Set(FastTier.fastRace(order: engines, ollamaWarm: RouterSettings.shared.ollamaHTTPReachable))
                var raced = ordered.filter { fastSet.contains($0.engine) }
                if raced.isEmpty { raced = Array(ordered.prefix(2)) } // only slow engines installed: still race, never sequential
                // `zeus --deep` keeps its long first-text allowance; a spoken turn gets 8 s.
                let budget: TimeInterval = deep ? 45 : Double(FastTier.firstTextBudgetMs) / 1000
                let deepReason = deep ? nil : DeepTrigger.reason(for: transcript, task: taskKind)
                let deepTier = FastTier.deepEngine(order: engines).flatMap { engine in
                    ordered.first { $0.engine == engine }.map { FastRaceRun.Tier(id: $0.id, provider: $0.provider) }
                }
                VoiceLog.log("route", "brain race \(raced.map(\.id).joined(separator: " + "))\(deepReason != nil && deepTier != nil ? ", deep behind: \(deepTier?.id ?? "")" : "")")
                // A turn that carries screenshots races only the engine that can see them; text-only engines wait and
                // answer (without the screen, and saying so) only if the image engine fails or times out.
                let groups = TalkSightPolicy.raceGroups(ids: raced.map(\.id), carriesImages: request.carriesDrawImage)
                let primary = raced.filter { groups.primary.contains($0.id) }
                let fallback = raced.filter { groups.fallback.contains($0.id) }
                let keepsDeep = TalkSightPolicy.keepsDeepTier(deepID: deepTier?.id, carriesImages: request.carriesDrawImage)
                func makeRace(_ tiers: [(engine: BrainEngineID, id: String, provider: BrainProvider)], _ turnRequest: BrainRequest,
                              deepTier: FastRaceRun.Tier?, deepReason: DeepTrigger.Reason?) -> FastRaceRun {
                    FastRaceRun(
                    tiers: tiers.map { FastRaceRun.Tier(id: $0.id, provider: $0.provider) },
                    request: turnRequest.with(deep: deep, firstTextBudget: budget),
                    deepTier: deepTier, deepReason: deepReason,
                    callbacks: FastRaceRun.Callbacks(
                        filler: { [weak self] in
                            guard speak, let self, fillerGate.take() else { return }
                            let line = AckLines.filler(personality: ZeusPersonality.current())
                            VoiceLog.log("timing", "filler at \(msSinceRelease()) ms, nothing streamed yet")
                            if let visual = ThinkingDraw.plan(line: line) {
                                self.showThinking(visual, speak: true)
                                self.say(line)
                                self.buddy.showCaption(visual.boltCaption(at: 0))
                            } else {
                                self.say(line)
                            }
                        },
                        tierFailed: { id, text in
                            if let engine = RouterEngine(rawValue: id) {
                                if RouterSettings.isQuotaError(text) || RouterSettings.isSignInError(text) {
                                    RouterSettings.shared.markExhausted(engine)
                                }
                                // A silent 8 s is not a reason to park an engine for 10 minutes: it only ranks last.
                            }
                            BrainLatencyBook.shared.recordFailure(id)
                            VoiceLog.logContent("route", text, prefix: "\(id) failed; detail ")
                        },
                        firstText: { id, ms in
                            winnerID = id
                            timingFirstToken = msSinceRelease()
                            VoiceLatency.shared.setBrain(engine: id, model: Self.modelLabel(id))
                            VoiceLatency.shared.mark(.firstToken)
                            VoiceLog.log("brain", "engine=\(id) first_token_ms=\(ms) images=\(request.screenshots.count)")
                            BrainLatencyBook.shared.record(id, firstTokenMs: Double(ms))
                        },
                        deliverDeep: { [weak self] text in
                            self?.deliverDeepAnswer(text, transcript: transcript, speak: speak)
                        }))
                }
                var race = makeRace(primary, request, deepTier: keepsDeep ? deepTier : nil, deepReason: keepsDeep ? deepReason : nil)
                fastRace = race
                VoiceLatency.shared.mark(.requestSent)
                do {
                    try await race.run { delta in parser.feed(delta).forEach(handle) }
                } catch where !fallback.isEmpty && !Task.isCancelled
                    && TalkSightPolicy.fallbackAllowed(spokeAnything: !spoken.isEmpty, actionStarted: actionStarted) {
                    // The image engine failed before saying anything: the text engines answer, and say they cannot see.
                    VoiceLog.log("route", "image engine failed; racing text engines \(fallback.map(\.id).joined(separator: " + "))")
                    let blindPrompt = TalkSightPolicy.withoutDrawInstructions(request.systemPrompt,
                                                                              drawInstructions: ZeusPrompt.drawInstructions())
                    let blind = request.with(screenshots: [], systemPrompt: blindPrompt, screenReason: .imageEngineFailed,
                                             carriesDrawImage: false)
                    // Marks or a pointer the image engine began are taken back before the text engine answers.
                    if drawBegun { presenter.clear(); drawBegun = false; drawActive = false }
                    if pointed { buddy.idle(); pointed = false }
                    // Nothing from the image race reached the parser's output, so its half-read tag is dropped.
                    parser = ZeusTagStreamParser()
                    race = makeRace(fallback, blind, deepTier: nil, deepReason: nil)
                    fastRace = race
                    try await race.run { delta in parser.feed(delta).forEach(handle) }
                }
                VoiceLog.log("brain", "engine=\(race.winnerID ?? "?") done_ms=\(max(0, Int(Date().timeIntervalSince(started) * 1000)))")
            }
            parser.finish().forEach(handle)
            if let rest = splitter.flush() {
                let index = spokenSentenceCount
                spokenSentenceCount += 1
                if speak {
                    let reveal = revealCallback(index, token: drawToken)
                    speaker.speak(Self.voiced(rest), onStart: reveal)
                } else if let ready = TalkDrawReveal.sentenceReady(index: index, speak: false, drawingReady: drawBegun) {
                    presenter.reveal(sentence: ready, token: drawToken)
                }
            }
            buddy.showCaption(Self.captionTail(spoken))
            buddy.hideCaption()
            // No Screen Recording: one log line and one plain notice per launch, never a permission prompt mid-turn.
            let sightLine = owesSightNotice ? sightNotice.take(permissionGranted: false) : nil
            if sightLine != nil {
                VoiceLog.log("screen", "Screen Recording is off, so Zeus cannot see the screen; owner told once this launch")
                NSLog("[ZEUS] screen sight: Screen Recording permission is off (told the owner once this launch)")
            }
            if !pointed { buddy.idle() }
            if let notice = sightLine {
                if let visual = ScreenSightDraw.from(message: notice) {
                    showScreenSight(visual, speak: speak)
                    if speak { speaker.speak(notice) } else { buddy.showCaption(notice); buddy.hideCaption() }
                    buddy.showCaption(visual.boltCaption(at: 0))
                } else if speak {
                    speaker.speak(notice)
                } else {
                    buddy.showCaption(notice)
                    buddy.hideCaption()
                }
            }
            if !result.actions.isEmpty { AvatarStatus.shared.flash(.done, for: 2) }
            // Defense in depth: a tag or control code split oddly across streamed chunks could
            // dodge the per-chunk pass above; run it once more now that the full reply is in hand.
            let personality = ZeusPersonality.current()
            let answer = PersonaReplyClamp.clamp(ResponseSanitizer.sanitize(spoken), transcript: transcript, personality: personality)
            if answer.isEmpty { VoiceLog.log("spoken", "(nothing)") } else { VoiceLog.logContent("spoken", answer) }
            ZeusSound.play(.voiceDone)
            lastAnswerAt = Date()
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
            if let visual = AnswerFailDraw.from(message: message) {
                showAnswerFail(visual, speak: speak)
                if speak { say(message) } else { buddy.showCaption(message); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if let visual = ClaudeToolDraw.from(line: message) {
                showClaudeTool(visual, speak: speak)
                if speak { say(message) } else { buddy.showCaption(message); buddy.hideCaption() }
                buddy.showCaption(visual.boltCaption(at: 0))
            } else if speak {
                say(message)
            } else {
                buddy.showCaption(message)
                buddy.hideCaption()
            }
        }
        result.spoken = PersonaReplyClamp.clamp(ResponseSanitizer.sanitize(spoken), transcript: transcript,
                                                 personality: ZeusPersonality.current())
        VoiceLatency.shared.finishWhenQuiet { [weak self] in self?.speaker.isSpeaking ?? false }
        if drawBegun { hideDrawingWhenAnswerEnds(token: drawToken) }
        if blockedByRestriction {
            // Said and captioned once (the flag is per turn), and the delivered answer says nothing ran.
            let note = Self.blockedActionNote
            sayControlOff(note, speak: speak)
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

    /// What the speaker runs when sentence `index` starts to play: show that sentence's marks.
    private func revealCallback(_ index: Int, token: UUID?) -> (@MainActor () -> Void)? {
        guard let token else { return nil }
        let presenter = presenter
        return { presenter.reveal(sentence: index, token: token) }
    }

    /// The marks go a few seconds after the last line has played (the presenter owns the delay).
    private func hideDrawingWhenAnswerEnds(token: UUID) {
        guard speaker.isSpeaking else { presenter.answerFinished(token: token); return }
        Task { @MainActor [weak self] in
            while let self, self.speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(80)) }
            self?.presenter.answerFinished(token: token)
        }
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

    /// Draws a secret Zeus will not point at, under the pointer.
    /// The caller speaks the full line. A missing control stays on the spark.
    private func showPointSecret(_ plan: PointSecretDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyPointSecret(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyPointSecret(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyPointSecret(_ plan: PointSecretDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
    }

    /// A spoken "point at" or "show me" becomes one allowlisted guide. The bolt is drawn
    /// whether or not captions or spoken replies are on. Speech uses the speak-replies setting.
    /// A miss stays on this path: the model does not invent a point. A bare secret is not pointed at.
    private func pointSpokenAsk(_ transcript: String, speak: Bool) -> TurnResult? {
        guard SpokenPointingAsk.blocksModel(transcript) else { return nil }
        let snapshot = AXSnapshotter.shared.latest ?? AXSnapshotter.shared.capture(budget: 0.2)
        if let snapshot {
            var candidates: [PointingProposalCandidate] = []
            var frames: [String: CGRect] = [:]
            var number = 1
            for element in snapshot.elements {
                guard number <= 99 else { break }
                guard let label = element.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty,
                      !element.isSecure, element.frame.width > 0, element.frame.height > 0 else { continue }
                let id = "t\(number)"
                candidates.append(PointingProposalCandidate(id: id, isSecure: false, label: label))
                frames[id] = element.frame
                number += 1
            }
            if let show = SpokenPointingAsk.show(in: transcript, candidates: candidates),
               let frame = frames[show.targetID],
               let screen = axFrameOnScreen(frame), screen.width > 0, screen.height > 0 {
                if speak { say(show.spoken) }
                let center = CGPoint(x: screen.midX, y: screen.midY)
                buddy.point(to: center, label: show.bolt, ring: screen)
                remember(transcript, show.spoken)
                return TurnResult(spoken: show.spoken)
            }
        }
        guard let held = SpokenPointingAsk.held(transcript) else { return nil }
        if let visual = PointSecretDraw.from(line: held.spoken) {
            showPointSecret(visual, speak: speak)
            if speak { say(held.spoken) }
            buddy.showCaption(visual.boltCaption(at: 0))
        } else {
            if speak { say(held.spoken) }
            buddy.showCaption(held.bolt)
        }
        remember(transcript, held.spoken)
        return TurnResult(spoken: held.spoken)
    }

    private func axFrameOnScreen(_ frame: CGRect) -> CGRect? {
        let displays: [DisplayMap] = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayMap(id: Int(id), frame: screen.frame, scale: Double(screen.backingScaleFactor))
        }
        guard !displays.isEmpty else { return nil }
        let mainID = NSScreen.main?.displayID.map { Int($0) }
        let mapper = ScreenCoordinateMapper(displays: displays, mainDisplayID: mainID)
        return mapper.convert(frame, from: .ax, to: .screen, context: MapContext())
    }

    /// The fuller answer from the background deep engine, after the quick one. It always shows in the notch caption;
    /// it is spoken only while the owner is still in the conversation (hands-free window, or within
    /// `FastTier.conversationWindowSeconds` of the quick answer) and not already talking again.
    private func deliverDeepAnswer(_ text: String, transcript: String, speak: Bool) {
        var parser = ZeusTagStreamParser()
        var plain = ""
        for output in parser.feed(text) + parser.finish() {
            if case .text(let piece) = output { plain += piece }
        }
        let clean = ResponseSanitizer.sanitize(ResponseSanitizer.stripArtifacts(plain))
        guard !clean.isEmpty else { return }
        var splitter = SentenceSplitter()
        var sentences = splitter.feed(clean)
        if let rest = splitter.flush() { sentences.append(rest) }
        let inWindow = wakeConversationActive || (lastAnswerAt.map { Date().timeIntervalSince($0) < FastTier.conversationWindowSeconds } ?? false)
        let speakIt = speak && inWindow && !listening
        VoiceLog.log("timing", "deep answer ready, spoken=\(speakIt)")
        VoiceLog.logContent("spoken", clean, prefix: "deep: ")
        buddy.showCaption("Here is the fuller answer. " + Self.captionTail(clean))
        buddy.hideCaption()
        if let visual = FullerAnswerDraw.plan(sentence: sentences.first ?? "") {
            showFullerAnswer(visual, speak: speakIt)
            buddy.showCaption(visual.boltCaption(at: 0))
        }
        if speakIt, SettingsStore.shared.bool("voice.speakReplies") {
            speaker.speak("Here is the fuller answer.")
            for sentence in sentences.prefix(4) { speaker.speak(Self.voiced(sentence)) }
        }
        history.append(Exchange(user: "(fuller answer to: \(transcript.prefix(80)))", assistant: String(clean.prefix(400))))
        if history.count > 10 { history.removeFirst(history.count - 10) }
    }

    /// A timer just finished. The notch already showed it. This draws it under the pointer.
    func timerFinished() {
        let line = TimerFinishedDraw.line
        if let visual = TimerFinishedDraw.from(line: line) {
            showTimerFinished(visual, speak: true)
            say(line)
            buddy.showCaption(visual.boltCaption(at: 0))
        } else {
            say(line)
        }
    }

    /// Speaks and captions a short message of ZEUS's own (errors, "Approved.").
    func say(_ text: String) {
        VoiceLog.logContent("spoken", text)
        if SettingsStore.shared.bool("voice.speakReplies") {
            seams.duckBegin()
            speaker.speak(Self.voiced(text))
            Task { @MainActor [weak self] in
                guard let self else { return }
                while self.speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(80)) }
                self.seams.duckEnd()
            }
        }
        buddy.showCaption(text)
        buddy.hideCaption()
    }

    /// What the voice is handed: no ominous trailing hedge, and no ellipsis in an Ultron reply.
    static func voiced(_ text: String) -> String {
        UltronSpeechText.prepared(PersonaCompliance.stripOminousHedges(text), personality: ZeusPersonality.current())
    }

    /// The words drawn beside a point. At most three short lines. A line that is too long stays off.
    static func pointLabel(_ raw: String?, fallback: String) -> String {
        guard let raw, let text = PointerGuideCaptionSplit.boltText(raw) else { return fallback }
        return text
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

    /// The model behind an engine id, for the latency line.
    static func modelLabel(_ id: String) -> String {
        switch id {
        case "anthropic-api": ModelCap.httpModel(.anthropic, tier: .fast) ?? "-"
        case "openai": ModelCap.httpModel(.openAI, tier: .fast) ?? "-"
        case "claude": (ModelCap.model(for: .claude, tier: .fast) ?? "default") + " cli"
        case "ollama": ModelCap.httpModel(.ollama, tier: .fast) ?? "-"
        default: "-"
        }
    }

    /// Draws the missing Claude command-line tool, under the pointer.
    /// The caller speaks the full line. A spoken answer failure is not this card.
    private func showClaudeTool(_ plan: ClaudeToolDraw, speak: Bool) {
        clearDrawingForNewTurn()
        let shot = illustrationShot()
        let draw = ExplainShowcase.scaled(plan.draw, toWidth: shot.pixelWidth, toHeight: shot.pixelHeight)
        let token = UUID()
        guard presenter.begin(draw, shot: shot, token: token) else { return }
        drawActive = true
        explainBegan = Date()
        let beats = plan.schedule.indexes
        if let first = beats.first { presenter.reveal(sentence: first, token: token) }
        flyClaudeTool(plan, at: 0, shot: shot)
        explainReveal = Task { @MainActor [weak self] in
            for (offset, beat) in beats.dropFirst().enumerated() {
                try? await Task.sleep(for: .seconds(ExplainBeatSchedule.gap))
                guard let self, !Task.isCancelled else { return }
                self.presenter.reveal(sentence: beat, token: token)
                let elapsed = Double(offset + 1) * ExplainBeatSchedule.gap
                self.flyClaudeTool(plan, at: elapsed, shot: shot)
                self.buddy.showCaption(plan.boltCaption(at: elapsed))
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishExplainDrawing(token: token, speak: speak)
        }
    }

    private func flyClaudeTool(_ plan: ClaudeToolDraw, at elapsed: TimeInterval, shot: ScreenShot) {
        guard let bolt = plan.guideBolt(at: elapsed) else { return }
        buddy.flight(to: boltScreen(bolt, shot: shot), label: plan.boltCaption(at: elapsed))
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
        if lowered.contains("in time") { return "No AI answered in time; try again." }
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
