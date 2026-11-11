import AppKit
import AVFoundation
import Observation
import Speech
import ZeusCore

/// Dictation settings, kept apart from the voice assistant's so each has its own key.
@MainActor
@Observable
final class DictationSettings {
    static let shared = DictationSettings()
    private let defaults: UserDefaults

    var enabled: Bool { didSet { defaults.set(enabled, forKey: "dictation.enabled") } }
    var language: DictationLanguage { didSet { defaults.set(language.title, forKey: "dictation.language") } }
    /// nil means no dictation key.
    var key: Shortcut? {
        didSet {
            defaults.set(Shortcut.stored(key), forKey: ShortcutStore.dictationKey)
            if key == Preferences.shared.pushToTalk && behavior == .pressToToggle {
                behavior = .holdToSpeak
            }
        }
    }
    /// Hold/release is the default. Toggle is available only when dictation has its own key.
    var behavior: DictationBehavior {
        didSet {
            if behavior == .pressToToggle && key == Preferences.shared.pushToTalk {
                behavior = .holdToSpeak
            }
            defaults.set(behavior.rawValue, forKey: "dictation.behavior")
        }
    }
    var availableBehaviors: [DictationBehavior] {
        DictationBehavior.choices(sharedWithTalkKey: key == Preferences.shared.pushToTalk)
    }
    var selectedBehavior: DictationBehavior {
        availableBehaviors.contains(behavior) ? behavior : .holdToSpeak
    }
    /// Switch to a mode that lists the frontmost app. Off by default: AI modes use your Claude plan.
    var autoSwitch: Bool { didSet { defaults.set(autoSwitch, forKey: "dictation.autoSwitch") } }
    var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: "dictation.restoreClipboard") } }
    var sounds: Bool { didSet { defaults.set(sounds, forKey: "dictation.sounds") } }
    /// Pause Music or Spotify while you dictate, then carry on.
    var pauseMedia: Bool { didSet { defaults.set(pauseMedia, forKey: "dictation.pauseMedia") } }
    /// 0 keeps history forever.
    var keepDays: Int { didSet { defaults.set(keepDays, forKey: "dictation.keepDays") } }
    /// Speech engine for dictation. Parakeet by default (fastest and most accurate here, see
    /// docs/dictation-bench.md); Apple fills in until the model is on this Mac.
    var engine: TranscriptionEngineKind { didSet { defaults.set(engine.rawValue, forKey: "dictation.engine") } }
    /// Voice turns (talk key, the hands-free turn after "Hey Zeus") also run through `engine`.
    /// Off by default: Apple's live words keep voice turns as quick as they are today.
    var engineForVoice: Bool { didSet { defaults.set(engineForVoice, forKey: "dictation.engineForVoice") } }
    /// Type the text key by key instead of pasting, everywhere.
    var alwaysType: Bool { didSet { defaults.set(alwaysType, forKey: "dictation.alwaysType") } }
    /// Apps that ignore ⌘V (remote desktops, VMs) get typed text.
    var typedApps: [String] { didSet { defaults.set(typedApps, forKey: "dictation.typedApps") } }
    /// Core Audio UID of the chosen microphone; nil follows the system input.
    var microphoneUID: String? { didSet { defaults.set(microphoneUID, forKey: "dictation.microphone") } }
    /// Show the text in a card to correct before it goes in (Return inserts, Esc cancels).
    var previewBeforeInsert: Bool { didSet { defaults.set(previewBeforeInsert, forKey: "dictation.preview") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "dictation.enabled") as? Bool ?? true
        language = DictationLanguage(persistedValue: defaults.string(forKey: "dictation.language"))
        let resolvedKey = ShortcutStore.loadDictation(defaults)
        key = resolvedKey
        let savedBehavior = defaults.string(forKey: "dictation.behavior")
            .flatMap(DictationBehavior.init(rawValue:)) ?? .holdToSpeak
        behavior = resolvedKey == Preferences.shared.pushToTalk ? .holdToSpeak : savedBehavior
        autoSwitch = defaults.object(forKey: "dictation.autoSwitch") as? Bool ?? false
        restoreClipboard = defaults.object(forKey: "dictation.restoreClipboard") as? Bool ?? true
        sounds = defaults.object(forKey: "dictation.sounds") as? Bool ?? true
        pauseMedia = defaults.object(forKey: "dictation.pauseMedia") as? Bool ?? true
        keepDays = defaults.object(forKey: "dictation.keepDays") as? Int ?? 30
        engine = defaults.string(forKey: "dictation.engine").flatMap(TranscriptionEngineKind.init(rawValue:)) ?? .parakeet
        engineForVoice = defaults.bool(forKey: "dictation.engineForVoice")
        alwaysType = defaults.bool(forKey: "dictation.alwaysType")
        typedApps = defaults.stringArray(forKey: "dictation.typedApps") ?? KeystrokeTyping.defaultBundleIDs
        microphoneUID = defaults.string(forKey: "dictation.microphone")
        // Auto-insert by default (P0 item C, QA7, Tony 3 Nov 23:58: "it should insert by
        // default"): releasing the key types straight into the focused field. The preview card
        // (Return inserts, Esc cancels) stays available as an opt-in setting.
        previewBeforeInsert = defaults.object(forKey: "dictation.preview") as? Bool ?? false
    }
}

/// Which speech session and controller turn may still write live words to the notch.
/// Queued updates are checked when they run, so a cancel or a newer turn drops them.
@MainActor
final class DictationTurnOwnership {
    private(set) var generation: UInt64 = 0
    private var active: (speechSessionID: Int, generation: UInt64)?

    func beginTurn() -> UInt64 {
        generation &+= 1
        active = nil
        return generation
    }

    func bind(speechSessionID: Int, generation turn: UInt64) {
        guard turn == generation else { return }
        active = (speechSessionID, turn)
    }

    func invalidate() {
        generation &+= 1
        active = nil
    }

    /// True while `turn` is the current one: not cancelled, not replaced.
    func owns(generation turn: UInt64) -> Bool { turn == generation }

    /// Stops live words for `turn` once it is current. The generation is NOT bumped: the turn
    /// still owns its own finish (history, status, delivery) until it is cancelled or replaced.
    func retire(generation turn: UInt64) {
        if turn == generation { active = nil }
    }

    func accepts(sessionID: Int, generation turn: UInt64) -> Bool {
        DictationPartialUpdateGate.accepts(
            queuedSpeechSessionID: sessionID, queuedControllerGeneration: turn,
            activeSpeechSessionID: active?.speechSessionID, activeControllerGeneration: active?.generation,
            currentControllerGeneration: generation)
    }

    /// Called off the main thread by the speech callback. `enqueue` hops to the main actor.
    nonisolated func route(sessionID: Int, generation turn: UInt64, text: String,
                           enqueue: (@escaping @MainActor @Sendable () -> Void) -> Void,
                           write: @escaping @MainActor @Sendable (String) -> Void) {
        enqueue { [self] in
            if accepts(sessionID: sessionID, generation: turn) { write(text) }
        }
    }
}

/// Everything one dictation turn needs after the key is released, captured once when the turn
/// begins. A later `begin()` rewrites the controller's shared `mode`/`targetApp`/`selection`;
/// this copy never changes.
struct DictationTurnContext {
    let generation: UInt64
    let mode: DictationMode
    let targetApp: NSRunningApplication?
    let selection: String?
    let useLocal: Bool
    let engine: (any TranscriptionEngine)?
    let insertionField: DictationInsertionTracker.Field?
}

/// What happens after release, with ownership checked after every await. A cancelled or
/// replaced turn returns `.superseded` before it touches history, status, toasts or the target.
/// `DictationController.finish()` runs exactly this; tests drive it with synthetic closures.
@MainActor
struct DictationFinishFlow {
    enum Result: Equatable {
        case superseded, empty, discarded
        case delivered(TextInserter.Outcome)
    }

    struct Heard {
        var text: String
        var engine: TranscriptionEngineKind
        var samples: [Float]
        /// Said with the result when the chosen engine failed and Apple took over.
        var note: String?

        init(text: String, engine: TranscriptionEngineKind, samples: [Float], note: String? = nil) {
            self.text = text
            self.engine = engine
            self.samples = samples
            self.note = note
        }
    }

    var isCurrent: () -> Bool
    var transcribe: () async -> Heard
    /// Live words stop for this turn; the turn itself stays the owner.
    var closePartials: () -> Void
    var process: (String) async -> String
    /// nil skips the preview card; a nil answer from the card discards the text.
    var review: ((String) async -> String?)?
    var deliver: (String) async -> TextInserter.Outcome
    var onEmpty: () -> Void
    var onDiscarded: () -> Void
    var onDelivered: (_ raw: String, _ text: String, _ outcome: TextInserter.Outcome, _ heard: Heard) -> Void

    func run() async -> Result {
        guard isCurrent() else { return .superseded }
        let heard = await transcribe()
        guard isCurrent() else { return .superseded }
        closePartials()
        let raw = heard.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            onEmpty()
            return .empty
        }
        var text = await process(raw)
        guard isCurrent() else { return .superseded }
        if let review {
            let reviewed = await review(text)
            guard isCurrent() else { return .superseded }
            guard let reviewed else {
                onDiscarded()
                return .discarded
            }
            text = reviewed
        }
        let outcome = await deliver(text)
        guard isCurrent() else { return .superseded }
        onDelivered(raw, text, outcome, heard)
        return .delivered(outcome)
    }
}

/// The end of a debug `dictate-file` turn: feed, focus the target, finish. Ownership is checked
/// after the feed and after the focus delay, so a stale inject never finishes a newer turn.
@MainActor
struct DictationInjectCompletion {
    var isCurrent: () -> Bool
    var sleep: (Int) async -> Void
    var feed: () async throws -> Bool
    var activate: () -> Void
    var finish: () -> Void

    /// True when this inject still owned the turn and asked it to finish.
    func run() async throws -> Bool {
        let fed = try await feed()
        guard fed, isCurrent() else { return false }
        activate()
        await sleep(120)
        guard isCurrent() else { return false }
        finish()
        return true
    }
}

/// Resumes the review continuation exactly once: first of the card's answer and the timeout.
private final class ReviewAnswerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }

    /// True only for the call that actually resumed the continuation.
    @discardableResult
    func resolve(_ answer: String?) -> Bool {
        let pending = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: answer)
        return pending != nil
    }
}

/// Hold the dictation key, speak, release: the words land in whatever app is in front.
/// Double-tap for hands-free; Escape cancels. Speech runs on the Mac (Apple on-device
/// recognition); an AI mode then rewrites the text with your existing Claude plan.
@MainActor
final class DictationController {
    private let topBar: TopBarModel
    private let settings = DictationSettings.shared
    private let speech = SpeechInput()
    private let ownership = DictationTurnOwnership()
    private let hotkey = HotkeyMonitor()
    private let store: DictationStore
    private var escapeMonitor: Any?
    private var startedAt = Date()
    private var targetApp: NSRunningApplication?
    private var selection: String?
    private var mode = DictationMode.builtIns[0]
    /// The running turn's immutable copy of mode, target, selection and engine.
    private var turnContext: DictationTurnContext?
    /// The chosen engine hears this turn (ready and chosen); Apple otherwise.
    private var useLocal = false
    private var pausedMedia = false
    /// Every dictation job (live turn, file, history re-run) as one state; `topBar.dictationPhase` only mirrors it.
    private(set) var flow: DictationFlow.State = .idle {
        didSet { topBar.dictationPhase = flow.phase }
    }
    /// The local model's download and load: one state, mirrored into `SpeechEngineStatus` for the views.
    private var modelState = ModelPreparation.State.idle
    private var modelTask: Task<Void, Never>?
    private var lastModelToken: UInt64 = 0
    let parakeet = ParakeetEngine()
    let parakeetUltra = ParakeetEngine(.parakeetUltra)
    let whisperKit = WhisperKitEngine()
    let whisper = WhisperCppEngine()
    let appleAnalyzer = AppleAnalyzerEngine()
    let apple = AppleSpeechEngine()
    let fasterWhisper = FasterWhisperEngine()
    let elevenLabs = ElevenLabsScribeEngine()
    let openAI = OpenAITranscribeEngine()
    private lazy var router = TranscriptionRouter(engines: TranscriptionEngineKind.allCases.map { engine($0) })
    /// The chosen engine for this turn, when it is ready.
    private var turnEngine: (any TranscriptionEngine)?
    /// The live session of a streaming engine (ElevenLabs) for this turn.
    private var turnStream: (any TranscriptionStream)?
    private let insertionTracker = DictationInsertionTracker()

    /// Every engine ZEUS offers, by kind.
    func engine(_ kind: TranscriptionEngineKind) -> any TranscriptionEngine {
        switch kind {
        case .parakeet: parakeet
        case .parakeetUltra: parakeetUltra
        case .whisperKit: whisperKit
        case .whisper: whisper
        case .appleAnalyzer: appleAnalyzer
        case .apple: apple
        case .fasterWhisper: fasterWhisper
        case .elevenLabs: elevenLabs
        case .openAI: openAI
        }
    }

    /// Cheap, synchronous readiness for the moment a key goes down. SpeechAnalyzer's state comes
    /// from the last check (Settings and launch refresh it); everything else is a file or key check.
    func isReadyNow(_ kind: TranscriptionEngineKind) -> Bool {
        switch kind {
        case .parakeet: parakeet.isDownloaded
        case .parakeetUltra: parakeetUltra.isDownloaded
        case .whisperKit: whisperKit.isDownloaded
        case .whisper: whisper.isDownloaded
        case .appleAnalyzer: SpeechEngineBoard.shared.states[.appleAnalyzer] == .ready
        case .fasterWhisper: fasterWhisper.isDownloaded
        case .elevenLabs, .openAI: CloudKeys.has(kind)
        case .apple: false
        }
    }

    /// The chosen speech engine when it is ready now; nil means Apple's live recognition.
    var readyEngine: (any TranscriptionEngine)? {
        settings.engine == .apple || !isReadyNow(settings.engine) ? nil : engine(settings.engine)
    }

    /// The person's vocabulary with the built-in names (Zeus, Jev, Claude, Codex, Murmure…).
    private var fullVocabulary: Vocabulary { DictationVocabularyPrompt.merged(store.vocabulary()) }
    private var hints: [String] { DictationVocabularyPrompt.terms(store.vocabulary()) }
    /// Rewrites text for AI modes. Injected so tests and snapshots never call a model.
    var rewrite: (String) async throws -> String = { $0 }

    init(topBar: TopBarModel, store: DictationStore) {
        self.topBar = topBar
        self.store = store
    }

    func start() {
        DictationHub.shared.controller = self
        RecorderPill.shared.attach(topBar)
        // Pruning only follows a clean read: a corrupt history file is set aside, never pruned around.
        if reloadModesAndHistory() { store.prune(olderThanDays: settings.keepDays) }
        hotkey.keyProvider = { [weak self] in
            guard let self, self.settings.enabled, let key = self.settings.key else { return nil }
            return key
        }
        hotkey.directPressProvider = { [weak self] in self?.settings.selectedBehavior == .pressToToggle }
        hotkey.role = .dictation
        hotkey.onPress = { [weak self] in self?.handleDictationKeyPress() }
        hotkey.onRelease = { [weak self] in self?.handleDictationKeyRelease() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
        hotkey.start()
        speech.onLevel = { [weak self] level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.topBar.pushDictationLevel(level) } }
        }
        let ownership = ownership
        speech.onIdentifiedPartial = { [weak self] sessionID, generation, text in
            ownership.route(sessionID: sessionID, generation: generation, text: text,
                            enqueue: { work in DispatchQueue.main.async { MainActor.assumeIsolated(work) } },
                            write: { text in self?.topBar.dictationPartial = text })
        }
        topBar.transcribeFile = { [weak self] url in self?.transcribe(file: url) }
        topBar.chooseFileToTranscribe = { [weak self] in self?.chooseFile() }
        topBar.insertText = { text in Task { _ = await TextInserter.insert(text) } }
        // Load the model early so the first dictation is as quick as the rest.
        if settings.engine == .parakeet, parakeet.isDownloaded { prepareModel(announce: false, explicit: false) }
        if settings.engine == .parakeetUltra, parakeetUltra.isDownloaded { Task { try? await parakeetUltra.prepare(progress: nil) } }
        Task { await SpeechEngineBoard.shared.refresh() }
    }

    private var effectiveBehavior: DictationBehavior {
        settings.selectedBehavior
    }

    private func handleDictationKeyPress() {
        switch effectiveBehavior.actionOnPress(isDictating: topBar.isDictating) {
        case .begin: begin()
        case .finish: finish()
        }
    }

    private func handleDictationKeyRelease() {
        if effectiveBehavior.finishesOnRelease { finish() }
    }

    /// Downloads (first time) and loads Parakeet in the background. `explicit` is a click on Download;
    /// a key press or launch passes false, so a failed download is not retried on every dictation.
    func prepareModel(announce: Bool = true, explicit: Bool = true) {
        lastModelToken &+= 1
        modelEvent(.startRequested(token: lastModelToken, trigger: explicit ? .explicit : .automatic,
                                   downloaded: parakeet.isDownloaded, announce: announce))
    }

    /// Stops a Parakeet download or load that is running; the state returns to idle.
    func cancelModelPreparation() { modelEvent(.cancelRequested) }

    private func modelEvent(_ event: ModelPreparation.Event) {
        let (next, effects) = ModelPreparation.reduce(modelState, event)
        guard next != modelState || !effects.isEmpty else { return }
        modelState = next
        // Settings and onboarding read SpeechEngineStatus; it only mirrors the state.
        let status = SpeechEngineStatus.shared
        status.progress = ModelPreparation.progress(of: next)
        status.problem = ModelPreparation.problem(of: next)
        if case .ready = next { status.refresh(parakeet) }
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: ModelPreparation.Effect) {
        switch effect {
        case .startWork(let token, _):
            modelTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await parakeet.prepare { fraction in
                        DispatchQueue.main.async { MainActor.assumeIsolated { self.modelEvent(.progress(token: token, fraction: fraction)) } }
                    }
                    modelEvent(.succeeded(token: token))
                    await SpeechEngineBoard.shared.refresh()
                } catch {
                    modelEvent(.failed(token: token, message: error.localizedDescription))
                }
            }
        case .cancelWork:
            modelTask?.cancel()
            modelTask = nil
            parakeet.cancelPreparation()
        case .announce(.downloading):
            topBar.show(.dictation("Downloading Parakeet, Apple speech meanwhile"))
        case .announce(.ready):
            topBar.show(.dictation("Parakeet is ready"))
        case .announce(.failed(let message)):
            // The live Settings card reads the board's message, so the reason stays on screen.
            SpeechEngineBoard.shared.message = "Parakeet download failed: \(message)"
            topBar.show(.dictation("Parakeet download failed, using Apple speech"))
        }
    }

    /// Returns false when a history file was unreadable (it was moved aside and a notice shown).
    @discardableResult
    func reloadModesAndHistory() -> Bool {
        topBar.dictationModes = store.modes()
        let load = store.loadHistory(limit: 50)
        topBar.dictationHistory = load.records
        guard !load.isClean else { return true }
        let count = load.problems.count
        topBar.show(.dictation(count == 1
            ? "A dictation history file was damaged. Saved as .corrupt, nothing deleted"
            : "\(count) dictation history files were damaged. Saved as .corrupt, nothing deleted"))
        return false
    }

    /// Mode files live here as JSON, one per mode; edit or add files and ZEUS picks them up.
    var modesFolder: URL { store.root.appendingPathComponent("modes", isDirectory: true) }

    var topBarModel: TopBarModel { topBar }

    /// Saves a custom mode (or an edit of a built-in one) as its JSON file.
    func saveMode(_ mode: DictationMode) {
        do { try store.save(mode) } catch {
            topBar.show(.dictation("Couldn't save the mode"))
        }
        reloadModesAndHistory()
    }

    /// Removes a custom mode's file. A built-in mode comes back as its original.
    func deleteMode(key: String) {
        try? FileManager.default.removeItem(at: modesFolder.appendingPathComponent("\(key).json"))
        if topBar.selectedModeKey == key { topBar.selectedModeKey = "voice" }
        reloadModesAndHistory()
    }

    var vocabulary: Vocabulary {
        get { store.vocabulary() }
        set {
            do { try store.save(newValue) } catch {
                topBar.show(.dictation("Couldn't save the vocabulary"))
            }
        }
    }

    // MARK: Microphone dictation

    /// Runs one event through `DictationFlow`, performs its effects, and says whether anything changed.
    @discardableResult
    private func apply(_ event: DictationFlow.Event) -> Bool {
        let before = flow
        let (next, effects) = DictationFlow.reduce(before, event)
        flow = next
        for effect in effects {
            switch effect {
            case .invalidateTurn:
                ownership.invalidate()
                insertionTracker.invalidate()
            case .releaseCapture:
                releaseCapture()
            case .busy:
                topBar.show(.dictation("Finish the current dictation first"))
            }
        }
        return next != before || !effects.isEmpty
    }

    /// Everything a running turn holds: the Escape monitor, the preview card, the recorder, the streaming
    /// session and the paused media.
    private func releaseCapture() {
        removeEscape()
        // A cancelled turn must not leave its preview card waiting on screen.
        Self.dismissPreviewCard()
        speech.cancel()
        speech.onSamples = nil
        turnStream?.cancel()
        turnStream = nil
        resumeMedia()
        topBar.dictationPartial = ""
    }

    func begin() {
        guard flow.canStartJob else { return }
        ExplanationAudioArbitration.yieldToNewCapture()
        fallbackNote = nil
        let speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        let languageAvailable = speech.configure(localeIdentifier: settings.language.localeIdentifier)
        turnEngine = readyEngine
        let local = turnEngine != nil
        // A local model only needs the microphone; Apple also needs Speech Recognition.
        let microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Apple recognition only runs on this Mac: a language without on-device support fails
        // closed (or is skipped when a local engine listens) instead of reaching Apple's servers.
        let appleOnDevice = speechAllowed && languageAvailable && speech.supportsOnDevice
        guard microphoneAllowed, appleOnDevice || local else {
            let reason = !speechAllowed
                ? "Allow Microphone and Speech Recognition in Zeus setup first."
                : languageAvailable
                    ? "On-device speech recognition isn't available for this language. Nothing was recorded. Choose another language or a local engine."
                    : "Apple Speech is unavailable for the selected language on this Mac."
            apply(.startFailed(reason: reason))
            topBar.show(.dictation(microphoneAllowed ? "Speech recognition is unavailable" : "Dictation needs the microphone"))
            return
        }
        if settings.engine == .parakeet, !parakeet.isDownloaded { prepareModel(explicit: false) }
        // Apple runs alongside a local model for the live words in the notch. The audio is
        // always kept so the dictation can be reprocessed later with another engine.
        speech.recognizes = appleOnDevice
        speech.recordsSamples = true
        speech.deviceUID = settings.microphoneUID
        useLocal = local
        targetApp = NSWorkspace.shared.frontmostApplication
        let insertionField = insertionTracker.beginTurn()
        mode = DictationMode.resolve(topBar.dictationModes, selectedKey: topBar.selectedModeKey,
                                     frontmostBundleID: targetApp?.bundleIdentifier, autoSwitch: settings.autoSwitch)
        selection = mode.useSelectedText ? TextInserter.selectedText() : nil
        let turnHints = hints
        speech.contextualStrings = turnHints
        turnStream?.cancel()
        turnStream = (turnEngine as? any StreamingTranscriptionEngine)?.openStream(hints: turnHints, language: settings.language.localeIdentifier)
        if let stream = turnStream {
            speech.onSamples = { samples in stream.send(samples) }
        } else {
            speech.onSamples = nil
        }
        let turnGeneration = ownership.beginTurn()
        do {
            let sessionID = try speech.start(controllerGeneration: turnGeneration)
            ownership.bind(speechSessionID: sessionID, generation: turnGeneration)
            turnContext = DictationTurnContext(generation: turnGeneration, mode: mode, targetApp: targetApp,
                                               selection: selection, useLocal: local, engine: turnEngine, insertionField: insertionField)
        } catch {
            ownership.invalidate()
            insertionTracker.invalidate()
            turnStream?.cancel()
            turnStream = nil
            apply(.startFailed(reason: error.localizedDescription))
            topBar.show(.dictation("Dictation could not start"))
            return
        }
        startedAt = Date()
        RecorderPill.markStarted(startedAt)
        topBar.dictationModeName = mode.name
        topBar.dictationModeSymbol = mode.symbol
        topBar.dictationPartial = ""
        apply(.micOpened(turn: turnGeneration))
        if settings.pauseMedia, topBar.nowPlaying?.isPlaying == true {
            topBar.musicCommand(.playPause)
            pausedMedia = true
        }
        cue(.dictationBegin)
        guard AccessibilityGate.trusted else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    /// Debug/E2E only (PLAN-QA7 P0 item J, "quiet hours"): while a real hold-to-dictate turn is
    /// already listening (key held via `begin()`), feeds a WAV file's audio into the exact same
    /// recorder/recognizer `finish()` reads from, instead of the live microphone -- so a
    /// quiet-hours run proves dictation, self-correction and auto-insert end to end without ever
    /// playing the phrase through the real speakers.
    func injectDictationFile(_ url: URL) async -> String {
        if topBar.isDictating { cancel() }
        for _ in 0..<60 {
            if flow == .idle { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        fallbackNote = nil
        let savedLocale = settings.language.localeIdentifier
        _ = speech.configure(localeIdentifier: "en-US")
        useLocal = false
        turnEngine = nil
        turnStream?.cancel()
        turnStream = nil
        speech.onSamples = nil
        speech.recognizes = true
        speech.recordsSamples = false
        targetApp = NSWorkspace.shared.frontmostApplication
        let insertionField = insertionTracker.beginTurn()
        mode = DictationMode.resolve(topBar.dictationModes, selectedKey: topBar.selectedModeKey,
                                     frontmostBundleID: targetApp?.bundleIdentifier, autoSwitch: settings.autoSwitch)
        selection = mode.useSelectedText ? TextInserter.selectedText() : nil
        speech.contextualStrings = hints
        let turnGeneration = ownership.beginTurn()
        let context = DictationTurnContext(generation: turnGeneration, mode: mode, targetApp: targetApp,
                                           selection: selection, useLocal: false, engine: nil, insertionField: insertionField)
        let sessionID: Int
        do {
            sessionID = try speech.startInjectOnly(controllerGeneration: turnGeneration)
            ownership.bind(speechSessionID: sessionID, generation: turnGeneration)
            turnContext = context
        } catch {
            ownership.invalidate()
            insertionTracker.invalidate()
            _ = speech.configure(localeIdentifier: savedLocale)
            return "ERROR \(error.localizedDescription)"
        }
        startedAt = Date()
        RecorderPill.markStarted(startedAt)
        topBar.dictationModeName = mode.name
        topBar.dictationModeSymbol = mode.symbol
        topBar.dictationPartial = ""
        apply(.micOpened(turn: turnGeneration))
        guard flow.isListening else {
            _ = speech.configure(localeIdentifier: savedLocale)
            return "ERROR not listening (hold the dictation key first)"
        }
        let historyCountBefore = topBar.dictationHistory.count
        do {
            // Inject-only E2E/debug always ends here. Hands-free (latch) mode keeps the mic open
            // after key-up, so `finishesOnRelease` is false and left the turn stuck or half-heard.
            // A cancelled or replaced inject must not focus the target or finish a newer turn.
            let completion = DictationInjectCompletion(
                isCurrent: { [ownership] in ownership.owns(generation: context.generation) },
                sleep: { try? await Task.sleep(for: .milliseconds($0)) },
                feed: { [speech] in try await speech.injectFile(url: url, expectedSession: sessionID) },
                activate: { context.targetApp?.activate() },
                finish: { [weak self] in self?.finish() })
            guard try await completion.run() else { return "ERROR dictate-file superseded" }
            loop: for _ in 0..<240 {
                guard ownership.owns(generation: context.generation) else { break loop }
                switch flow {
                case .done, .failed, .idle: break loop
                default: try? await Task.sleep(for: .milliseconds(50))
                }
            }
            // Restoring the locale cancels the speech session: never do that to a newer turn's.
            guard ownership.owns(generation: context.generation) else { return "ERROR dictate-file superseded" }
            _ = speech.configure(localeIdentifier: savedLocale)
            let failure: String? = if case .failed(let message) = flow { message } else { nil }
            let history = topBar.dictationHistory.map {
                DictationFileInject.TurnSnapshot(inserted: $0.inserted, resultText: $0.result)
            }
            var field = TextInserter.focusedFieldText()
            var reply = DictationFileInject.replyAfterInject(historyCountBefore: historyCountBefore,
                                                             history: history,
                                                             failureMessage: failure,
                                                             fieldText: field)
            if reply == "ERROR paste not verified",
               let turn = DictationFileInject.turnFromInject(historyCountBefore: historyCountBefore, history: history),
               turn.inserted {
                context.targetApp?.activate()
                try? await Task.sleep(for: .milliseconds(200))
                guard ownership.owns(generation: context.generation) else { return "ERROR dictate-file superseded" }
                _ = await deliver(turn.resultText, context: context, allowClipboardFallback: false)
                try? await Task.sleep(for: .milliseconds(400))
                guard ownership.owns(generation: context.generation) else { return "ERROR dictate-file superseded" }
                field = TextInserter.focusedFieldText()
                reply = DictationFileInject.replyAfterInject(historyCountBefore: historyCountBefore,
                                                             history: history,
                                                             failureMessage: failure,
                                                             fieldText: field)
            }
            return reply
        } catch {
            if ownership.owns(generation: context.generation) { _ = speech.configure(localeIdentifier: savedLocale) }
            return "ERROR \(error.localizedDescription)"
        }
    }

    func cancel() {
        guard flow.isActive else { return }
        apply(.cancelRequested)
        topBar.show(.dictation("Dictation cancelled"))
    }

    func finish() {
        guard flow.isListening else { return }
        // Everything below reads this turn's context, never the shared vars a replacement rewrites.
        guard let context = turnContext, ownership.owns(generation: context.generation) else { return }
        removeEscape()
        apply(.finishRequested)
        let audioMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let released = Date()
        let generation = context.generation
        let stream = turnStream
        // These values belong to this finish flow, never to a later controller turn.
        var correctionRequested = false
        var deliveryMessage: String?
        let isCurrent: () -> Bool = { [ownership] in ownership.owns(generation: generation) }
        let review: ((String) async -> String?)? = settings.previewBeforeInsert
            ? { [self] text in
                reviewTimedOut = false
                let title = correctionRequested ? "Replace entire previous dictation" : context.mode.name
                return await Self.reviewWithTimeout(text, modeName: title, onTimeout: { [self] in
                    // Nobody answered: keep the words on the clipboard instead of losing them.
                    reviewTimedOut = true
                    let kept = DictationPreviewCard.shared.currentText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(kept.isEmpty ? text : kept, forType: .string)
                })
            }
            : nil
        let flow = DictationFinishFlow(
            isCurrent: isCurrent,
            transcribe: { [self] in await transcribeTurn(context: context, stream: stream) },
            closePartials: { [self] in
                ownership.retire(generation: generation)
                resumeMedia()
            },
            process: { [self] raw in
                if let replacement = TextInsertionReceipt.correctionPayload(raw) {
                    correctionRequested = true
                    // Only a command actually spoken by the person may request replacement.
                    // AI mode rewriting cannot invent a destructive cross-turn command.
                    return TranscriptPolish.prepareForInsert(fullVocabulary.apply(to: replacement))
                }
                return await process(raw, mode: context.mode, selection: context.selection,
                                     appName: context.targetApp?.localizedName, turn: generation, source: .live,
                                     isCurrent: isCurrent)
            },
            review: review,
            deliver: { [self] text in
                if correctionRequested {
                    let result = await deliverCorrection(text, context: context, restoreAfterPreview: review != nil)
                    deliveryMessage = result.message
                    return result.outcome
                }
                return await deliver(text, context: context, allowClipboardFallback: true)
            },
            onEmpty: { [self] in
                VoiceLog.log("dictation", "transcript empty")
                apply(.failed(turn: generation, reason: "No speech was heard."))
                topBar.show(.dictation("No speech heard"))
                cue(.failure)
            },
            onDiscarded: { [self] in
                insertionTracker.invalidate()
                apply(.dismissed(turn: generation))
                topBar.show(.dictation(reviewTimedOut ? "No answer in 5 minutes. Text copied, press ⌘V to paste" : "Dictation discarded"))
                reviewTimedOut = false
            },
            onDelivered: { [self] raw, text, outcome, heard in
                let record = DictationRecord(duration: audioMs, processingTime: Int(Date().timeIntervalSince(released) * 1000),
                                             modeKey: context.mode.key, modeName: context.mode.name, rawResult: raw, result: text,
                                             appBundleID: context.targetApp?.bundleIdentifier, appName: context.targetApp?.localizedName,
                                             inserted: outcome == .pasted, engine: heard.engine.rawValue)
                // Metadata only: dictated words never go to the diagnostic log.
                VoiceLog.log("dictation", "transcript \(raw.count) characters, \(record.wordCount) words")
                switch outcome {
                case .pasted: VoiceLog.log("dictation", "inserted \(record.wordCount) words")
                case .copiedOnly: VoiceLog.log("dictation", "clipboard, not inserted")
                case .unconfirmed: VoiceLog.log("dictation", "replacement attempted, acknowledgment unavailable")
                }
                var saveFailed = false
                do { try store.save(record) } catch { saveFailed = true }
                if !heard.samples.isEmpty {
                    do { try store.saveAudio(heard.samples, for: record.id) } catch { saveFailed = true }
                }
                topBar.dictationHistory.insert(record, at: 0)
                apply(.succeeded(turn: generation))
                let written = deliveryMessage ?? (outcome == .pasted ? "\(record.wordCount) words written" : "Copied. Press ⌘V to paste.")
                let base = heard.note.map { "\($0) \(written)." } ?? written
                topBar.show(.dictation(saveFailed ? "\(base) Couldn't save to history." : base))
                cue(.dictationEnd)
            })
        Task { @MainActor in _ = await flow.run() }
    }

    /// Said with the result when the chosen engine failed and Apple took over.
    private var fallbackNote: String?

    /// How long the "Check before writing" card may wait before the turn is discarded, so an
    /// unanswered card can never leave the phase stuck in `.transcribing`.
    private static let reviewTimeoutSeconds = 300
    /// Set when the last preview card timed out, so the toast says the text was copied.
    private var reviewTimedOut = false

    /// The preview card's answer, or nil (discard) when nobody answers in time; `onTimeout` runs first then.
    private static func reviewWithTimeout(_ text: String, modeName: String,
                                          onTimeout: @escaping @MainActor @Sendable () -> Void) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let gate = ReviewAnswerGate(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(reviewTimeoutSeconds))
                guard !Task.isCancelled else { return }
                // Timeout wins: close the card itself so its review task resolves and no stale
                // card is left to overlap a later review.
                if gate.resolve(nil) {
                    onTimeout()
                    dismissPreviewCard()
                }
            }
            Task { @MainActor in
                let answer = await DictationPreviewCard.shared.review(text, modeName: modeName)
                timer.cancel()
                gate.resolve(answer)
            }
        }
    }

    /// Closes a visible preview card through its own Cancel path, which resumes its review.
    private static func dismissPreviewCard() {
        for window in NSApp.windows {
            if let panel = window as? PreviewPanel, panel.isVisible { _ = panel.onKey(.cancel) }
        }
    }

    /// The chosen engine's text when it is in use, else Apple's live transcript. An engine error
    /// never loses the dictation: Apple's words are already there, and the notch says so.
    /// Runs for `context`'s turn only: once cancelled or replaced it touches no shared state.
    private func transcribeTurn(context: DictationTurnContext,
                                stream: (any TranscriptionStream)?) async -> DictationFinishFlow.Heard {
        let isCurrent: () -> Bool = { [ownership] in ownership.owns(generation: context.generation) }
        let live = await speech.stop()
        guard isCurrent() else { return .init(text: "", engine: .apple, samples: []) }
        let samples = speech.takeSamples()
        speech.onSamples = nil
        turnStream = nil
        guard context.useLocal, let engine = context.engine, !samples.isEmpty else {
            stream?.cancel()
            let note = !context.useLocal && settings.engine.isCloud
                ? "\(settings.engine.title) needs its key, Apple took over." : nil
            return .init(text: live, engine: .apple, samples: samples, note: note)
        }
        let (text, kind, note) = await resolve(engine: engine, stream: stream, samples: samples, live: live,
                                               isCurrent: isCurrent)
        return .init(text: text, engine: kind, samples: samples, note: note)
    }

    /// Runs the chosen engine (or finishes its live stream), then applies the fallback decision.
    /// Returns the text, the engine that produced it and the note to show when Apple took over.
    /// `isCurrent` is false once a dictation turn was cancelled or replaced: no stale toast then.
    private func resolve(engine: any TranscriptionEngine, stream: (any TranscriptionStream)?, samples: [Float],
                         live: String, isCurrent: () -> Bool = { true }) async -> (String, TranscriptionEngineKind, String?) {
        let language = settings.language.localeIdentifier
        let outcome: DictationFallback.Outcome
        do {
            let text: String
            if let stream { text = try await stream.finish() } else { text = try await engine.transcribe(samples: samples, hints: hints, language: language) }
            outcome = .text(text)
        } catch {
            outcome = .failed(error.localizedDescription)
            if isCurrent() { SpeechEngineBoard.shared.message = "\(engine.kind.title): \(error.localizedDescription)" }
        }
        switch DictationFallback.decide(chosen: engine.kind, outcome: outcome, live: live) {
        case .keep(let text):
            return (text, engine.kind, nil)
        case .useLive(let text, let toast):
            if let toast, isCurrent() { topBar.show(.dictation(toast)) }
            return (text, .apple, toast.map { _ in "\(engine.kind.title) failed, Apple took over." })
        case .retranscribe(let toast):
            if isCurrent() { topBar.show(.dictation(toast)) }
            let fallback = try? await router.transcribe(samples: samples, preferred: .apple, hints: hints, language: language)
            return (fallback?.text ?? "", fallback?.engine ?? .apple, "\(engine.kind.title) failed, Apple took over.")
        case .nothing:
            return ("", engine.kind, nil)
        }
    }

    /// Voice turns (talk key, hands-free) through the chosen engine, when "Use for voice commands
    /// too" is on and the engine is ready. nil keeps Apple's live recognition.
    var voiceEngine: (any TranscriptionEngine)? {
        settings.engineForVoice ? readyEngine : nil
    }

    /// A voice turn's recording through `engine`, falling back to Apple's live words.
    func transcribeVoice(samples: [Float], live: String, with engine: any TranscriptionEngine) async -> String {
        guard !samples.isEmpty else { return live }
        let (text, _, _) = await resolve(engine: engine, stream: nil, samples: samples, live: live)
        return fullVocabulary.apply(to: TranscriptPolish.tidy(text))
    }

    /// Vocabulary fixes, then the mode's AI rewrite if it has one. A failed rewrite keeps your words.
    private func process(_ raw: String, mode: DictationMode, selection: String?, appName: String?,
                         turn: UInt64, source: DictationFlow.Source,
                         isCurrent: () -> Bool = { true }, didEnterRewriting: () -> Void = {}) async -> String {
        // P0 item D, QA7: fix a self-correction ("no wait", "actually", "sorry", "scratch that"
        // ...) before anything else touches the text, so only the corrected version gets to AI
        // rewriting or insertion.
        let fixed = TranscriptPolish.prepareForInsert(fullVocabulary.apply(to: raw))
        guard mode.usesAI else { return fixed }
        guard isCurrent() else { return fixed }
        // The flow refuses when another job owns the phase: the words go in as they were heard.
        guard apply(.rewriteStarted(turn: turn, source: source)) else { return fixed }
        didEnterRewriting()
        let prompt = mode.buildPrompt(transcript: fixed, selectedText: selection,
                                      clipboard: mode.useClipboard ? NSPasteboard.general.string(forType: .string) : nil,
                                      appName: appName)
        do {
            let rewritten = try await rewrite(prompt).trimmingCharacters(in: .whitespacesAndNewlines)
            return rewritten.isEmpty ? fixed : rewritten
        } catch {
            if isCurrent() { topBar.show(.dictation("AI rewrite failed, pasted your words")) }
            return fixed
        }
    }

    /// What the delivery gate says right now for `context`'s turn: `.abort` once the turn was
    /// cancelled or replaced, else the target's live state (PID and bundle ID, fail closed).
    private func deliveryVerdict(for context: DictationTurnContext, allowClipboardFallback: Bool) -> TextInserter.DeliveryGate.Action {
        guard ownership.owns(generation: context.generation) else { return .abort }
        let target = context.targetApp.map { TextInserter.DeliveryGate.identity(of: $0) }
        let state = TextInserter.DeliveryGate.state(
            target: target, terminated: context.targetApp?.isTerminated ?? true,
            probe: TextInserter.DeliveryGate.live)
        return TextInserter.DeliveryGate.action(for: state, allowClipboardFallback: allowClipboardFallback)
    }

    private func deliver(_ text: String, context: DictationTurnContext, allowClipboardFallback: Bool) async -> TextInserter.Outcome {
        // A new ordinary turn supersedes any older replacement receipt, even on clipboard fallback.
        insertionTracker.invalidate()
        // Hold Shift while releasing to press Return after pasting.
        // Paste where the person was, even if the notch took a click meanwhile.
        if let app = context.targetApp, app != NSWorkspace.shared.frontmostApplication {
            app.activate()
            // The preview card had focus: only type once the target app is truly in front.
            let back = await FrontmostHandoff.waitUntilFrontmost(
                target: app.bundleIdentifier, current: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
                sleep: { try? await Task.sleep(for: .milliseconds(40)) })
            guard ownership.owns(generation: context.generation) else { return .copiedOnly }
            if !back {
                if allowClipboardFallback {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                return .copiedOnly
            }
        }
        // Only a target that is still alive, frontmost and focused gets an automatic paste.
        switch deliveryVerdict(for: context, allowClipboardFallback: allowClipboardFallback) {
        case .paste:
            break
        case .clipboardOnly:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copiedOnly
        case .abort:
            return .copiedOnly
        }
        let pressReturn = context.mode.autoSend || NSEvent.modifierFlags.contains(.shift)
        let before = insertionTracker.prepareInsertion(in: context.insertionField)
        // The same verdict is asked again at every delayed paste, Return and typed piece.
        let check: TextInserter.DeliveryCheck = { [self] in
            let verdict = deliveryVerdict(for: context, allowClipboardFallback: allowClipboardFallback)
            if verdict == .paste, let field = context.insertionField, !insertionTracker.matchesFocus(field) {
                return allowClipboardFallback ? .clipboardOnly : .abort
            }
            return verdict
        }
        let outcome: TextInserter.Outcome
        if KeystrokeTyping.shouldType(bundleID: context.targetApp?.bundleIdentifier, alwaysType: settings.alwaysType, typedApps: settings.typedApps) {
            outcome = await TextInserter.type(text, pressReturn: pressReturn, deliveryCheck: check)
        } else {
            outcome = await TextInserter.insert(text, pressReturn: pressReturn, restoreClipboard: settings.restoreClipboard,
                                                deliveryCheck: check)
        }
        if outcome == .pasted, check() == .paste {
            await insertionTracker.acknowledge(text, before: before, target: context.insertionField,
                                              sendsReturn: pressReturn, isCurrent: { check() == .paste })
        }
        return outcome
    }

    /// A correction replaces the entire last acknowledged turn, never a guessed earlier word.
    /// Unsupported fields receive an explicit select-and-paste recovery instead of deletion.
    private func deliverCorrection(_ text: String, context: DictationTurnContext, restoreAfterPreview: Bool) async
        -> (outcome: TextInserter.Outcome, message: String) {
        let isCurrent = { [ownership] in ownership.owns(generation: context.generation) }
        guard isCurrent() else { return (.copiedOnly, "Correction cancelled") }
        // The optional preview can temporarily take focus. Restore only the original app; the
        // retained element and exact owned range still have to pass the replacement executor.
        if restoreAfterPreview, let app = context.targetApp, app != NSWorkspace.shared.frontmostApplication {
            app.activate()
            _ = await FrontmostHandoff.waitUntilFrontmost(
                target: app.bundleIdentifier, current: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
                sleep: { try? await Task.sleep(for: .milliseconds(40)) })
        }
        guard isCurrent() else { return (.copiedOnly, "Correction cancelled") }
        let result = await insertionTracker.correct(text, target: context.insertionField, isCurrent: isCurrent)
        guard isCurrent() else { return (.copiedOnly, "Correction cancelled") }
        switch result {
        case .replaced:
            return (.pasted, "Replaced the entire previous dictation")
        case .unavailable:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return (.copiedOnly, "Couldn't verify the previous dictation. Replacement copied; select the entire previous dictation, then press ⌘V.")
        case .unconfirmed:
            return (.unconfirmed, "Correction could not be confirmed. Check the field before retrying; the replacement is in history.")
        case .superseded:
            return (.copiedOnly, "Correction cancelled")
        }
    }

    private func removeEscape() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func resumeMedia() {
        guard pausedMedia else { return }
        pausedMedia = false
        topBar.musicCommand(.playPause)
    }

    private func cue(_ event: ZeusSound.Event) {
        guard settings.sounds else { return }
        ZeusSound.play(event)
    }

    // MARK: History: reprocess and corrections

    /// Runs a past dictation again with another mode, and with another engine when its audio
    /// was kept. The history entry is replaced; nothing is pasted.
    @discardableResult
    func reprocess(_ id: String, modeKey: String, engine: TranscriptionEngineKind?) async -> DictationRecord? {
        guard let record = topBar.dictationHistory.first(where: { $0.id == id }) ?? store.history(limit: .max).first(where: { $0.id == id }),
              let newMode = topBar.dictationModes.first(where: { $0.key == modeKey }) else { return nil }
        // A live dictation owns the phase: never start or reset anything beside it.
        guard !topBar.isDictating else {
            topBar.show(.dictation("Finish the current dictation first"))
            return nil
        }
        let started = Date()
        // This call owns the phase only once the flow accepted its `.rewriting`, and only while no
        // dictation turn has begun since (every turn bumps the generation).
        let turn = ownership.beginTurn()
        var enteredRewriting = false
        var raw: String?
        if let engine, let samples = store.audio(for: id) {
            raw = try? await router.transcribe(samples: samples, preferred: engine, hints: hints, language: settings.language.localeIdentifier).text
        }
        let text = await process(raw ?? record.rawResult, mode: newMode, selection: nil, appName: record.appName,
                                 turn: turn, source: .history,
                                 isCurrent: { [topBar] in !topBar.isDictating },
                                 didEnterRewriting: { enteredRewriting = true })
        if enteredRewriting { apply(.dismissed(turn: turn)) }
        let updated = record.reprocessed(mode: newMode, rawResult: raw, result: text,
                                         engine: raw == nil ? nil : engine?.rawValue,
                                         processingTime: Int(Date().timeIntervalSince(started) * 1000))
        replace(updated)
        return updated
    }

    /// Saves a hand-corrected result and returns what the vocabulary could learn from it.
    func correct(_ id: String, to text: String) -> VocabularyCapture.Suggestion {
        guard var record = topBar.dictationHistory.first(where: { $0.id == id }) else { return .init(replacements: [], words: []) }
        let suggestion = VocabularyCapture.suggest(original: record.result, corrected: text)
        record.result = text
        replace(record)
        return suggestion
    }

    func learn(_ suggestion: VocabularyCapture.Suggestion) {
        let merged = VocabularyCapture.merge(suggestion, into: vocabulary)
        vocabulary = merged
        topBar.vocabularyDraft = merged.editableText
    }

    func hasAudio(_ id: String) -> Bool { store.hasAudio(for: id) }

    func deleteRecord(_ id: String) {
        store.delete(id)
        topBar.dictationHistory.removeAll { $0.id == id }
    }

    private func replace(_ record: DictationRecord) {
        do { try store.save(record) } catch {
            topBar.show(.dictation("Couldn't save the change to history"))
        }
        if let index = topBar.dictationHistory.firstIndex(where: { $0.id == record.id }) {
            topBar.dictationHistory[index] = record
        }
    }

    /// Makes a mode the default, by key or name ("email", "Email"). Unknown keys are ignored.
    func selectMode(_ key: String) {
        guard let match = topBar.dictationModes.first(where: { $0.key == key || $0.name.lowercased() == key.lowercased() }) else {
            topBar.show(.dictation("No mode called \(key)"))
            return
        }
        topBar.selectedModeKey = match.key
        topBar.show(.dictation("Mode: \(match.name)"))
    }

    /// For links and shortcuts: start, or finish if already listening (hands-free style).
    func toggle() {
        if flow.isListening { finish() } else { begin() }
    }

    // MARK: File transcription

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { transcribe(file: url) }
    }

    func transcribe(file url: URL) {
        // A file never starts beside a live turn or another file: it would take the phase from a
        // microphone that is still recording.
        guard flow.canStartJob else {
            topBar.show(.dictation("Finish the current dictation first"))
            return
        }
        let turn = ownership.beginTurn()
        topBar.dictationModeName = "File"
        topBar.dictationModeSymbol = "doc.text"
        apply(.fileRequested(turn: turn))
        if let engine = readyEngine {
            transcribeLocally(file: url, with: engine, turn: turn)
            return
        }
        transcribeWithApple(file: url, turn: turn)
    }

    private func transcribeLocally(file url: URL, with engine: any TranscriptionEngine, turn: UInt64) {
        let started = Date()
        let vocabulary = fullVocabulary
        let hints = hints
        Task { @MainActor in
            let loaded = await Task.detached { Result { try AudioSamples.load(url) } }.value
            // Cancelled (or replaced) while the file was read: leave the phase and clipboard alone.
            guard flow.turn == turn else { return }
            let samples: [Float]
            switch loaded {
            case .success(let read): samples = read
            case .failure(let error):
                // Apple reads the file itself below; say why our reader could not.
                topBar.show(.dictation("Couldn't read the file here: \(error.localizedDescription)"))
                samples = []
            }
            let heard = try? await engine.transcribe(samples: samples, hints: hints, language: settings.language.localeIdentifier)
            guard flow.turn == turn else { return }
            guard let text = heard, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                transcribeWithApple(file: url, turn: turn)
                return
            }
            let fixed = vocabulary.apply(to: TranscriptPolish.tidy(text))
            let record = DictationRecord(duration: samples.count / 16, processingTime: Int(Date().timeIntervalSince(started) * 1000),
                                         modeKey: "file", modeName: url.lastPathComponent, rawResult: text, result: fixed,
                                         source: "file", engine: engine.kind.rawValue)
            var saved = true
            do { try store.save(record) } catch { saved = false }
            topBar.dictationHistory.insert(record, at: 0)
            topBar.copyText(fixed)
            apply(.succeeded(turn: turn))
            topBar.show(.dictation(saved ? "File transcribed and copied" : "File transcribed and copied. Couldn't save to history."))
        }
    }

    /// Also the fallback when the local engine heard nothing: it keeps the same `turn`.
    private func transcribeWithApple(file url: URL, turn: UInt64) {
        let locale = settings.language.localeIdentifier.map(Locale.init(identifier:)) ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            apply(.failed(turn: turn, reason: "Speech recognition is unavailable for the selected language."))
            topBar.show(.dictation("Speech recognition is unavailable for the selected language"))
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            apply(.failed(turn: turn, reason: "On-device speech recognition isn't available for this language, so the file was not sent to Apple."))
            topBar.show(.dictation("On-device recognition unavailable for this language"))
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.addsPunctuation = true
        request.contextualStrings = hints
        request.requiresOnDeviceRecognition = true
        let started = Date()
        let vocabulary = fullVocabulary
        OffMainAudioCallbacks.recognizeFinal(recognizer, request: request) { [weak self] text, message in
            guard let self, self.flow.turn == turn else { return }
            guard !text.isEmpty else {
                self.apply(.failed(turn: turn, reason: message ?? "No speech found in the file."))
                self.topBar.show(.dictation("No speech found in the file"))
                return
            }
            let fixed = vocabulary.apply(to: text)
            let record = DictationRecord(duration: 0, processingTime: Int(Date().timeIntervalSince(started) * 1000),
                                         modeKey: "file", modeName: url.lastPathComponent, rawResult: text, result: fixed,
                                         source: "file", engine: TranscriptionEngineKind.apple.rawValue)
            var saved = true
            do { try self.store.save(record) } catch { saved = false }
            self.topBar.dictationHistory.insert(record, at: 0)
            self.topBar.copyText(fixed)
            self.apply(.succeeded(turn: turn))
            self.topBar.show(.dictation(saved ? "File transcribed and copied" : "File transcribed and copied. Couldn't save to history."))
        }
    }
}
