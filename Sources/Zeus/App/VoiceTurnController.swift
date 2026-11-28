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
        let fast = FastPath.shared
        if let plan = fast.confirmedPlan(for: transcript) {
            return await perform(plan, engine: "Rules", transcript: transcript, finalAt: finalAt, speak: speak)
        }
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
        } else {
            say(spoken)
        }
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
        } else {
            if let shown { showMemoryKept(shown, speak: speak) }
            if speak { say(reply) } else { buddy.showCaption(reply); buddy.hideCaption() }
            if let shown { buddy.showCaption(shown.boltCaption(at: 0)) }
        }
        remember(transcript, reply)
        return TurnResult(spoken: reply)
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
                        guard let first = beats.first else { return nil }
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
