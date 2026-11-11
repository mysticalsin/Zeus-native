import AppKit
import Observation
import ZeusCore

/// One visual conversation. Production work begins only through an explicit Chat
/// control. Model output has no connection to FastActions or VoiceTurnController.
@MainActor @Observable
final class ExplanationController {
    enum Phase: Equatable { case idle, loading, thinking, preparingSpeech, speaking, paused, captions, completed }
    private(set) var phase: Phase = .idle
    private(set) var scene: ExplanationScene?
    private(set) var history: ExplanationHistory?
    private(set) var caption = ""
    private(set) var problem: String?
    private(set) var saveProblem: String?
    private(set) var isReceiving = false
    private(set) var isReplaying = false
    private(set) var inputAttemptID: UUID?
    private(set) var isClosing = false
    var draft = ""
    var selection: String?
    var muted = false
    var reduceMotion = false
    var rate = 1.0
    var deviceUID: String?
    var useInstalledWhisper = false
    var includeSnapshot = false
    var localInput: (any TranscriptionEngine)?
    var onSubmission: ((String) -> Void)?
    /// One desktop pointing turn: the app-built context and, only with the owner's upload consent,
    /// the frozen snapshot. Consumed by the next `submit()`.
    struct PointingTurn: Sendable {
        var context: PointingContext
        var snapshot: ExplanationScreenSnapshot?
        /// For the desktop card: the turn's display, the focused text input's frame and the pointer,
        /// all AppKit global points. Nothing here is sent to a model.
        var displayID: UInt32? = nil
        var inputArea: CGRect? = nil
        var pointer: CGPoint? = nil
    }
    var desktopTurn: PointingTurn?
    /// The desktop overlay's windows, for own-process window-policy checks.
    var overlayWindows: [NSWindow] { overlay.ownedWindows }
    var overlayVisible: Bool { overlay.isVisible }
    /// Window level of the desktop overlay. Chat keeps `.floating`; pointing sits above menus.
    var overlayLevel: NSWindow.Level {
        get { overlay.windowLevel }
        set { overlay.windowLevel = newValue; desktopCard.windowLevel = newValue }
    }
    /// The desktop card's windows, for own-process window-policy checks.
    var cardWindows: [NSWindow] { desktopCard.ownedWindows }
    var cardVisible: Bool { desktopCard.isVisible }
    var cardLayout: ExplanationCardLayout? { desktopCard.lastLayout }
    /// Real first audio start of a pointing turn (not the request, not the first token).
    @ObservationIgnored var onSpeechStart: (() -> Void)?
    /// A cue was admitted by real playback; the argument is the admitted target scene.
    @ObservationIgnored var onReveal: ((ExplanationScene) -> Void)?
    /// The turn finished (nil) or failed (the error; `problem` already holds user-facing copy).
    @ObservationIgnored var onTurnEnded: ((Error?) -> Void)?
    /// Listening produced no usable text, or the microphone failed.
    @ObservationIgnored var onEmptyInput: (() -> Void)?
    /// Marks the model asked for that were not grounded and were dropped before render.
    private(set) var droppedUngroundedMarks = 0
    private var activePointing: PointingTurn?
    private var pointingFirstBeatSeen = false
    private var desktopSessionStart: Date?
    let microphone: ExplanationMicrophone
    let screenContext: ExplanationScreenContext
    private let overlay: ExplanationOverlay
    private let desktopCard: ExplanationDesktopCard
    /// Non-capture objects the current beat creates, and the anchors last built from a live capture.
    private var beatObjectIDs = Set<String>()
    private var cardAnchors: PointingCardAnchors?
    private let provider: any ExplanationModelProviding
    private let speech: ExplanationSpeechRenderQueue
    private let player: ExplanationAudioPlayer
    private var store: ExplanationHistoryStore?
    private let storeFactory: (() throws -> ExplanationHistoryStore)?
    private var conversationID: UUID?
    private var requestedConversationID: UUID?
    private var generation = UUID()
    private var turnID: UUID?
    private var playback: ExplanationPlayback?
    private var presentation: ExplanationPresentation?
    private var replayPresentation: ExplanationReplayPresentation?
    private var baseline: ExplanationScene?
    private var projected: ExplanationScene?
    private var admission: (UUID, ExplanationHistory.ModelEventKey)?
    private var work: Task<Void, Never>?
    private var inputWork: Task<Void, Never>?
    private var prepared: [String: ExplanationPreparedAudio] = [:]
    private var capacity: CheckedContinuation<Void, Error>?
    private var replayEvents: [ExplanationEvent] = []
    private var completedBeatIDs = Set<String>()
    private var saveWork: Task<Void, Never>?
    private var pendingSaves: [UUID: ExplanationHistory] = [:]
    private var failedSaves: [UUID: ExplanationHistory] = [:]
    private var savingSnapshot: ExplanationHistory?
    private var savedCheckpoints: [UUID: UUID] = [:]
    private var linkedHistoryIDs = Set<UUID>()
    private let acquireAudio: () throws -> Void
    private let releaseAudio: () -> Void
    private var ownsAudio = false
    private var diagnostics: ExplanationDiagnostics
    private var diagnosticTurn: ExplanationDiagnostics.TurnToken?
    private var visualSubmissionPending = false
    private let processSample: () -> (cpuSeconds: Double?, physicalFootprintBytes: UInt64?)

    init(provider: any ExplanationModelProviding, speechProvider: any SpeechOutputProvider,
         player: ExplanationAudioPlayer = .init(), microphone: ExplanationMicrophone = .init(),
         screenContext: ExplanationScreenContext = .init(), overlay: ExplanationOverlay = .init(),
         desktopCard: ExplanationDesktopCard = .init(), store: ExplanationHistoryStore? = nil,
         storeFactory: (() throws -> ExplanationHistoryStore)? = nil,
         acquireAudio: @escaping () throws -> Void = {}, releaseAudio: @escaping () -> Void = {},
         diagnosticsClock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         processSample: @escaping () -> (cpuSeconds: Double?, physicalFootprintBytes: UInt64?) = {
             #if canImport(AppKit)
             let sample = ProcessEnergy.sample()
             let bytes = sample.residentMB * 1_048_576
             // The existing sampler reports zero if task_info fails. Keep that
             // unavailable instead of presenting a zero memory measurement.
             return (sample.cpuSeconds.isFinite && sample.cpuSeconds >= 0 ? sample.cpuSeconds : nil,
                     bytes.isFinite && bytes > 0 && bytes <= Double(1 << 50) ? UInt64(bytes) : nil)
             #else
             return (nil, nil)
             #endif
         }) {
        self.provider = provider; speech = .init(provider: speechProvider); self.player = player
        self.microphone = microphone; self.screenContext = screenContext; self.overlay = overlay
        self.desktopCard = desktopCard
        self.store = store; self.storeFactory = storeFactory
        self.acquireAudio = acquireAudio; self.releaseAudio = releaseAudio
        self.diagnostics = .init(clock: diagnosticsClock); self.processSample = processSample
        player.onObservation = { [weak self] observation in self?.observed(observation) }
        screenContext.onInvalidation = { [weak self] _ in self?.overlay.hide() }
    }

    var isBusy: Bool { isReceiving || [.thinking, .preparingSpeech, .speaking, .paused, .captions].contains(phase) }
    var canInteract: Bool {
        guard !isClosing, let history else { return false }
        return history.canonicalScene.sessionID == requestedConversationID
    }
    var wantsDisplayClock: Bool { phase == .speaking && !reduceMotion }
    var canReplay: Bool { !replayEvents.isEmpty && !isBusy && baseline != nil }
    var canUndo: Bool { history?.canUndo == true && !isBusy && !isReplaying }
    var canRedo: Bool { history?.canRedo == true && !isBusy && !isReplaying }
    var hasUnsavedHistory: Bool {
        !pendingSaves.isEmpty || !failedSaves.isEmpty || saveWork != nil
            || (history.map { $0.revision > 0 && savedCheckpoints[$0.id] != $0.lastCheckpointID } ?? false)
    }
    var currentDuration: Double { playback?.currentEvent.flatMap { prepared[$0.beatID]?.chunk.duration } ?? 0 }
    var position: Double { playback?.position ?? 0 }

    func open(conversationID id: UUID) async {
        requestedConversationID = id
        guard !isClosing, conversationID != id || history == nil else { return }
        stop(); screenContext.clear(); overlay.hide()
        if store == nil, (history?.revision ?? 0) > 0 {
            problem = "This explanation is only in memory. Restore local storage before switching to another conversation."
            return
        }
        guard failedSaves.count < 50 || failedSaves.values.contains(where: { $0.canonicalScene.sessionID == id }) else {
            problem = "Local history cannot be saved. Resolve the storage error before opening another explanation."
            return
        }
        let token = UUID(); generation = token; conversationID = id; phase = .loading
        history = nil; scene = nil; problem = nil; caption = ""; replayEvents = []; baseline = nil
        do {
            await saveWork?.value
            guard generation == token else { return }
            var loaded: ExplanationHistory?
            // A failed write remains an owned, recoverable record across Chat switches.
            loaded = failedSaves.values.filter { $0.canonicalScene.sessionID == id }.max(by: { $0.updatedAt < $1.updatedAt })
            if let store, loaded == nil {
                let list = try await store.list()
                guard generation == token else { return }
                if !list.failures.isEmpty { saveProblem = "Some saved explanations could not be read. They were left untouched." }
                if loaded == nil, let summary = list.records.filter({ $0.sessionID == id }).max(by: { $0.updatedAt < $1.updatedAt }) {
                    loaded = try await store.load(id: summary.id)
                    savedCheckpoints[summary.id] = summary.checkpointID
                }
            }
            guard generation == token else { return }
            let value = try loaded ?? ExplanationHistory(scene: .init(sessionID: id, sceneID: UUID()),
                                                         title: "Visual explanation", at: Date())
            history = value; scene = value.canonicalScene; phase = .idle
            if store == nil { saveProblem = "Local history is unavailable. This explanation will remain in memory only." }
        } catch {
            guard generation == token else { return }
            phase = .idle; problem = "Saved explanation could not be opened. Your saved file was left untouched."
        }
    }

    /// A desktop turn has no open Chat conversation, so it owns a session-scoped, in-memory history
    /// (never written to disk). A session is reused for follow-ups and replaced after `maxAge`.
    func prepareDesktopSession(maxAge: TimeInterval = 600) {
        guard !isClosing else { return }
        desktopCard.end() // A new hold starts a new turn: the last card goes.
        if let history, let started = desktopSessionStart, Date().timeIntervalSince(started) < maxAge,
           history.canonicalScene.sessionID == requestedConversationID { return }
        stop(); screenContext.clear(); overlay.hide()
        let id = UUID()
        do {
            let value = try ExplanationHistory(scene: .init(sessionID: id, sceneID: UUID()), title: "Desktop help", at: Date())
            generation = UUID(); conversationID = id; requestedConversationID = id
            history = value; scene = value.canonicalScene; phase = .idle; problem = nil; caption = ""
            replayEvents = []; baseline = nil; desktopSessionStart = Date()
            saveProblem = nil
        } catch { problem = "Zeus could not start a pointing session." }
    }

    func submit() {
        guard canInteract else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 16_384, history != nil else { return }
        let pointing = desktopTurn; desktopTurn = nil
        if pointing == nil { onSubmission?(text) }
        linkedHistoryIDs.insert(history!.id)
        stop(); draft = ""; problem = nil; isReplaying = false
        activePointing = pointing; pointingFirstBeatSeen = false
        beatObjectIDs = []; cardAnchors = nil
        // The card is bound to this turn's generation token (stop() above issued a new one).
        if pointing != nil { desktopCard.begin(token: generation) }
        do {
            if let pointing {
                // Capture-space marks need the scene to carry this capture's identity.
                var next = history!.canonicalScene
                next.objects = next.objects.filter { $0.value.space != .capture }
                next.captureID = pointing.context.captureID
                try history!.applyUserScene(next, baseRevision: history!.revision, at: Date())
            }
            let turn = UUID(); turnID = turn
            diagnosticTurn = diagnostics.beginTurn(identity: turn)
            sampleDiagnosticResources()
            _ = try history!.beginTurn(turn, at: Date())
            try history!.appendMessage(role: .user, text: text, at: Date())
            let start = history!.canonicalScene
            baseline = start; projected = start; scene = start
            presentation = try .init(scene: start)
            playback = try .init(sessionID: start.sessionID, turnID: turn, sceneID: start.sceneID,
                                 baseRevision: start.revision, mode: muted ? .captions : .audible)
            _ = try playback!.setRate(rate)
            replayEvents = []; completedBeatIDs = []; caption = ""; phase = .thinking; isReceiving = true
            queueSave()
            let request = ExplanationModelRequest(turnID: turn, scene: start, history: history!.messages, prompt: text,
                                                  snapshot: pointing != nil ? pointing?.snapshot
                                                      : (includeSnapshot ? screenContext.snapshot : nil),
                                                  pointing: pointing?.context)
            includeSnapshot = false
            let token = generation
            work = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.provider.respond(request) { [weak self] event in
                        guard let self, self.generation == token, self.turnID == turn else { throw CancellationError() }
                        try await self.receive(event, generation: token)
                    }
                    guard self.generation == token else { return }
                    self.isReceiving = false; self.updatePhase()
                } catch {
                    guard self.generation == token, !Task.isCancelled else { return }
                    self.fail(error)
                }
            }
        } catch { fail(error) }
    }

    private func receive(_ event: ExplanationEvent, generation token: UUID) async throws {
        try Task.checkCancellation()
        guard generation == token, let turnID, let projected else { throw CancellationError() }
        let event = resolvedForRender(event)
        let future = try ExplanationSceneReducer.applying(event, to: projected, activeTurn: turnID)
        while !muted && prepared.count >= 2 {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard capacity == nil else { continuation.resume(throwing: ExplanationAudioError.busy); return }
                    capacity = continuation
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    self?.releaseCapacity(throwing: CancellationError())
                }
            }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
        }
        self.projected = future
        if !isReplaying { replayEvents.append(event) }
        let enqueued = try playback!.enqueue(event)
        try process(enqueued)
        if !muted {
            if !ownsAudio { try acquireAudio(); ownsAudio = true }
            if phase != .speaking { phase = .preparingSpeech }
            let audio = try await speech.render(.init(event: event))
            try Task.checkCancellation()
            guard generation == token, self.turnID == turnID else { throw CancellationError() }
            try player.register(audio); prepared[event.beatID] = audio
            let effects = try playback!.prepare(audio.chunk)
            try process(effects)
        }
        updatePhase()
    }

    /// Pointing turns only: replace targetID marks with app-placed geometry and drop ungrounded
    /// marks. The returned event is protocol v1, so every downstream stage is unchanged.
    private func resolvedForRender(_ event: ExplanationEvent) -> ExplanationEvent {
        guard let context = activePointing?.context else { return event }
        let resolution = PointingSceneResolver.resolve(event, context: context)
        droppedUngroundedMarks += resolution.droppedObjects
        return resolution.event
    }

    private func observed(_ observation: ExplanationPlaybackObservation) {
        guard playback != nil else { return }
        do {
            let effects = try playback!.observe(observation)
            try process(effects)
            if case .failed = playback?.state { throw ExplanationAudioError.invalidPlayback }
            updatePhase()
        } catch { fail(error) }
    }

    private func process(_ effects: [ExplanationPlaybackEffect]) throws {
        for effect in effects {
            switch effect {
            case .audio(let command): player.execute(command)
            case .startBeat(let event):
                caption = event.speech.text
                beatObjectIDs = Self.createdCardObjectIDs(in: event)
                if activePointing != nil, !isReplaying, !pointingFirstBeatSeen {
                    pointingFirstBeatSeen = true; onSpeechStart?()
                }
                if !isReplaying, !muted, let diagnosticTurn {
                    diagnostics.recordFirstAudioStart(for: diagnosticTurn)
                }
                if !isReplaying {
                    let key = ExplanationHistory.ModelEventKey(event)
                    let id = try history!.stageModelEvent(key: key, cueCount: event.cues.count)
                    admission = (id, key)
                    try history!.startModelEvent(admissionID: id, key: key, at: Date())
                }
                try presentation!.begin(event)
            case .reveal(let cue):
                try presentation!.apply(cue)
                if activePointing != nil, !isReplaying { onReveal?(presentation!.targetScene) }
                if !isReplaying, let diagnosticTurn {
                    visualSubmissionPending = true
                    if !muted, let playback {
                        diagnostics.recordCueSchedulerLateness(for: diagnosticTurn,
                            actualMediaTime: playback.presentationTime, dueMediaTime: cue.presentationTime)
                    }
                }
                if !isReplaying, let (id, key) = admission {
                    try history!.admitCue(admissionID: id, key: key, cueIndex: cue.cueIndex,
                                          scene: presentation!.targetScene, at: Date())
                }
            case .finishBeat(let event):
                if !isReplaying, let (id, key) = admission {
                    try history!.finishModelEvent(admissionID: id, key: key); admission = nil
                    try history!.appendMessage(role: .assistant, text: event.speech.text, at: Date()); queueSave()
                    completedBeatIDs.insert(event.beatID)
                }
                if let audio = prepared.removeValue(forKey: event.beatID) { player.unregister(audio.chunk.id) }
                sampleDiagnosticResources()
                releaseCapacity()
            case .frame(let time):
                scene = try presentation!.sample(at: time, reduceMotion: reduceMotion || muted)
                if visualSubmissionPending, !isReplaying, let diagnosticTurn {
                    diagnostics.recordFirstVisualStateSubmitted(for: diagnosticTurn)
                    visualSubmissionPending = false
                }
            case let .replay(events, cues, time):
                guard let baseline else { throw ExplanationFailure.invalid("missing replay baseline") }
                if replayPresentation == nil { replayPresentation = try .init(scene: baseline) }
                scene = try replayPresentation!.sample(events: events, cues: cues, at: time, reduceMotion: reduceMotion || muted)
            case .replayFrame(let time):
                guard let replayPresentation else { throw ExplanationFailure.invalid("missing replay presentation") }
                scene = try replayPresentation.sample(at: time, reduceMotion: reduceMotion || muted)
            }
        }
        if let scene, screenContext.annotationContext != nil {
            _ = overlay.present(scene: scene, context: screenContext, reduceMotion: reduceMotion)
        }
        updateDesktopCard()
    }

    /// Non-capture objects a beat creates: the beat's own share of the card.
    private static func createdCardObjectIDs(in event: ExplanationEvent) -> Set<String> {
        var ids = Set<String>()
        for cue in event.cues {
            for operation in cue.operations {
                switch operation {
                case .create(let object), .connect(let object): if object.space != .capture { ids.insert(object.id) }
                default: break
                }
            }
        }
        return ids
    }

    /// Pointing turns only: charts, cards, diagrams and 3D have no overlay surface, so they go to the
    /// desktop card, beside (never over) what the owner pointed at. Capture-space marks stay on the overlay.
    private func updateDesktopCard() {
        guard let pointing = activePointing, !isReplaying, let scene else { return }
        if let capture = screenContext.annotationContext {
            let marks = scene.objects.values.filter { $0.space == .capture && $0.captureID == capture.geometry.captureID }
            cardAnchors = PointingCardAnchorBuilder.make(
                context: pointing.context, marks: marks, capture: capture,
                inputArea: pointing.inputArea.map { ExplanationRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) })
        }
        // The capture lease can lapse mid-turn; keep the last anchors so the card does not jump.
        let anchors = cardAnchors ?? PointingCardAnchorBuilder.make(
            pointer: pointing.pointer.map { ExplanationVector3(x: $0.x, y: $0.y) },
            inputArea: pointing.inputArea.map { ExplanationRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) })
        desktopCard.update(.init(token: generation, scene: scene, caption: caption, beatIDs: beatObjectIDs,
                                 anchors: anchors, displayID: pointing.displayID, pointer: pointing.pointer))
    }

    /// Stop freezes the sampled pose, invalidates every asynchronous generation,
    /// and retains only cues already admitted by actual playback/manual advance.
    func stop() {
        let stoppingDiagnosticTurn = diagnosticTurn
        if let stoppingDiagnosticTurn { diagnostics.beginCancellation(for: stoppingDiagnosticTurn) }
        defer {
            sampleDiagnosticResources()
            if let stoppingDiagnosticTurn {
                diagnostics.finishCancellation(for: stoppingDiagnosticTurn)
                diagnostics.endTurn(stoppingDiagnosticTurn)
            }
            diagnosticTurn = nil; visualSubmissionPending = false
        }
        let wasReplay = isReplaying
        let sampled: ExplanationScene?
        if let presentation {
            do { sampled = try presentation.sample(at: playback?.presentationTime ?? 0, reduceMotion: reduceMotion || muted) }
            catch {
                // A safe final target does not imply every interpolated pose is safe.
                // Preserve the last published pose if this sample fails validation.
                if let last = scene, let canonical = history?.canonicalScene,
                   last.sessionID == canonical.sessionID, last.sceneID == canonical.sceneID {
                    sampled = try? ExplanationSceneReducer.restoring(last, atRevision: canonical.revision)
                } else { sampled = nil }
            }
        } else { sampled = nil }
        generation = UUID(); turnID = nil
        inputAttemptID = nil
        work?.cancel(); work = nil; inputWork?.cancel(); inputWork = nil
        if screenContext.isCapturing { screenContext.cancel() }
        microphone.cancel(); speech.cancelAll(); player.stopAll(); prepared.removeAll()
        releaseCapacity(throwing: CancellationError())
        if let (id, key) = admission { try? history?.cancelModelEvent(admissionID: id, key: key) }
        admission = nil
        if !wasReplay {
            replayEvents = replayEvents.filter { completedBeatIDs.contains($0.beatID) }
            if !replayEvents.isEmpty { replayEvents[replayEvents.count - 1].isFinal = true }
        }
        if !wasReplay, let sampled, let canonical = history?.canonicalScene, sampled != canonical {
            do { try history!.freezePlayback(scene: sampled, baseRevision: canonical.revision, at: Date()) }
            catch { problem = "The interrupted scene could not be saved. The last committed scene is retained." }
        }
        if playback != nil { _ = playback!.cancel() }
        playback = nil; presentation = nil; replayPresentation = nil; projected = nil
        activePointing = nil
        isReceiving = false; isReplaying = false; phase = .idle; scene = history?.canonicalScene
        if ownsAudio { ownsAudio = false; releaseAudio() }
        overlay.hide(); desktopCard.end(); queueSave()
    }

    func pauseOrResume() {
        guard canInteract, playback != nil else { return }
        do { try process(phase == .paused ? playback!.resume() : playback!.pause()); updatePhase() }
        catch { fail(error) }
    }
    func advanceCaption() {
        guard canInteract, muted, playback != nil else { return }
        do { let effects = try playback!.advanceCaption(); try process(effects); updatePhase() }
        catch { fail(error) }
    }
    func changeRate(_ value: Double) {
        guard !isClosing else { return }
        do { if playback != nil { let effects = try playback!.setRate(value); try process(effects) }; rate = value }
        catch { fail(error) }
    }
    func seek(_ value: Double) {
        guard canInteract, let event = playback?.currentEvent, prepared[event.beatID] != nil else { return }
        do {
            if !isReplaying {
                if let (id, key) = admission { try history!.cancelModelEvent(admissionID: id, key: key); admission = nil }
                let pose = try presentation!.sample(at: playback!.presentationTime, reduceMotion: reduceMotion)
                try history!.freezePlayback(scene: pose, baseRevision: history!.revision, at: Date()); queueSave()
                // Scrubbing is a read-only playback preview. Never admit future
                // model edits into the canonical graph after a backwards seek.
                isReplaying = true; isReceiving = false
                replayEvents = replayEvents.filter { completedBeatIDs.contains($0.beatID) }
                if !replayEvents.isEmpty { replayEvents[replayEvents.count - 1].isFinal = true }
                work?.cancel(); work = nil; speech.cancelAll(); releaseCapacity(throwing: CancellationError())
            }
            let effects = try playback!.seek(beatID: event.beatID, position: value, stopAfterBeat: true)
            try process(effects); updatePhase()
        }
        catch { fail(error) }
    }
    func setMuted(_ value: Bool) {
        guard value != muted else { return }
        // The explicit mode change ends this turn; replay/next request uses the
        // selected mode, with no fabricated silent clock or resumed stale audio.
        stop(); muted = value
    }
    func sampleAudioClock() { player.observeDisplayClock() }
    func displayClockActive(_ active: Bool) { player.externalDisplayClockActive = active }

    /// In-memory numeric aggregates. Reading this explicitly takes one process
    /// sample; there is no diagnostics timer, network request or automatic export.
    func diagnosticsReport() -> ExplanationDiagnostics.Report {
        sampleDiagnosticResources()
        return diagnostics.snapshot()
    }
    private func sampleDiagnosticResources() {
        guard let diagnosticTurn else { return }
        let sample = processSample()
        diagnostics.recordProcessSample(for: diagnosticTurn, cumulativeCPUSeconds: sample.cpuSeconds,
                                        physicalFootprintBytes: sample.physicalFootprintBytes)
    }

    func replay() {
        guard canInteract, canReplay, let baseline, let first = replayEvents.first else { return }
        let events = replayEvents
        stop(); isReplaying = true; problem = nil; turnID = first.turnID; projected = baseline; scene = baseline
        do {
            presentation = try .init(scene: baseline)
            playback = try .init(sessionID: baseline.sessionID, turnID: first.turnID, sceneID: baseline.sceneID,
                                 baseRevision: baseline.revision, mode: muted ? .captions : .audible)
            _ = try playback!.setRate(rate)
            isReceiving = true; phase = .preparingSpeech
            let token = generation
            work = Task { [weak self] in
                guard let self else { return }
                do {
                    for event in events { try await self.receive(event, generation: token) }
                    guard self.generation == token else { return }
                    self.isReceiving = false; self.updatePhase()
                } catch { if self.generation == token, !Task.isCancelled { self.fail(error) } }
            }
        } catch { fail(error) }
    }

    func edit(_ operation: ExplanationOperation) {
        guard canInteract, !isReplaying else { return }
        stop()
        do {
            guard let current = history?.canonicalScene else { return }
            let next = try ExplanationSceneReducer.applyingOperations([operation], to: current, resultingRevision: current.revision + 1)
            try history!.applyUserScene(next, baseRevision: current.revision, at: Date())
            scene = history!.canonicalScene; replayEvents = []; queueSave()
        } catch { problem = "That change cannot be applied to the current scene." }
    }
    func undo() { mutateHistory { try $0.undo(at: Date()) } }
    func redo() { mutateHistory { try $0.redo(at: Date()) } }
    private func mutateHistory(_ change: (inout ExplanationHistory) throws -> Void) {
        guard canInteract, !isReplaying else { return }
        stop()
        do { if history != nil { try change(&history!); scene = history!.canonicalScene; replayEvents = []; queueSave() } }
        catch { problem = "That history change is unavailable." }
    }

    @discardableResult
    func beginListening() -> UUID? {
        guard canInteract else { return nil }
        stop(); problem = nil
        let token = generation
        inputAttemptID = token
        inputWork = Task { [weak self] in
            guard let self, self.generation == token, self.inputAttemptID == token, !Task.isCancelled else { return }
            do {
                let selection: ExplanationInputSelection
                if self.useInstalledWhisper {
                    guard let engine = self.localInput else { throw ExplanationMicrophoneError.engineNotReady }
                    selection = .installedLocal(engine)
                } else { selection = .appleOnDevice }
                try await self.microphone.start(selection: selection, deviceUID: self.deviceUID)
            } catch {
                if self.generation == token, !Task.isCancelled {
                    self.inputAttemptID = nil
                    self.problem = "Microphone input is unavailable. Check the selected device and macOS permissions, or type your request."
                    self.onEmptyInput?()
                }
            }
        }
        return token
    }
    func finishListening() {
        guard let inputAttemptID else { return }
        finishListening(attemptID: inputAttemptID)
    }
    func finishListening(attemptID: UUID) {
        guard inputAttemptID == attemptID else { return }
        if microphone.state == .idle || microphone.state == .requestingPermission { stop(); return }
        guard microphone.state == .listening else { return }
        let token = generation
        inputWork = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.microphone.finish()
                guard self.generation == token else { return }
                self.draft = text; self.submit()
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.desktopTurn = nil; self.onEmptyInput?() }
            } catch {
                if self.generation == token, !Task.isCancelled {
                    self.inputAttemptID = nil
                    self.problem = "No transcription was available. Try again or type your request."
                    self.desktopTurn = nil; self.onEmptyInput?()
                }
            }
        }
    }
    func cancelListening(attemptID: UUID) {
        guard inputAttemptID == attemptID else { return }
        stop()
    }
    func flushPendingSaves() async {
        if store == nil, let storeFactory {
            do { store = try storeFactory(); queueSave() }
            catch { saveProblem = "Local storage is still unavailable. The explanation remains in memory." }
        }
        queueSave()
        for (id, snapshot) in failedSaves {
            // A retry cannot place an older failed checkpoint behind a newer
            // same-record write which has already left the pending dictionary.
            if let savingSnapshot, savingSnapshot.id == id,
               savingSnapshot.checkpoints.last!.ordinal >= snapshot.checkpoints.last!.ordinal { continue }
            if let pending = pendingSaves[id], pending.checkpoints.last!.ordinal >= snapshot.checkpoints.last!.ordinal { continue }
            pendingSaves[id] = snapshot
        }
        startSaveWorker()
        await saveWork?.value
    }
    func beginClosing() { isClosing = true; stop() }
    func resumeAfterCancelledQuit() { isClosing = false }

    func captureDisplay(_ displayID: UInt32) {
        guard canInteract, displayID != 0 else { return }
        stop(); problem = nil; includeSnapshot = false
        let token = generation
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.screenContext.captureSelectedDisplay(displayID)
                guard self.generation == token, var next = self.history?.canonicalScene else { return }
                next.objects = next.objects.filter { $0.value.space != .capture }
                next.captureID = snapshot.geometry.captureID
                try self.history!.applyUserScene(next, baseRevision: self.history!.revision, at: Date())
                self.scene = self.history!.canonicalScene; self.replayEvents = []; self.queueSave()
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.problem = "Snapshot unavailable. Select a connected display and grant Screen Recording in macOS Settings yourself."
            }
        }
    }
    func clearSnapshot() {
        guard canInteract else { return }
        stop(); screenContext.clear(); includeSnapshot = false
        guard var next = history?.canonicalScene else { return }
        next.objects = next.objects.filter { $0.value.space != .capture }; next.captureID = nil
        do {
            try history!.applyUserScene(next, baseRevision: history!.revision, at: Date())
            scene = history!.canonicalScene; replayEvents = []; queueSave()
        } catch { problem = "The snapshot was removed, but its scene history could not be updated." }
    }
    @discardableResult
    func deleteConversation(_ id: UUID, expectedHistoryID: UUID? = nil) async -> Bool {
        let ownedHistoryID = expectedHistoryID ?? (history?.canonicalScene.sessionID == id ? history?.id : nil)
        if let ownedHistoryID { linkedHistoryIDs.insert(ownedHistoryID) }
        if conversationID == id { stop(); history = nil; scene = nil; conversationID = nil; screenContext.clear() }
        if store == nil, let storeFactory { store = try? storeFactory() }
        guard let store else { saveProblem = "Linked history deletion could not be verified while storage is unavailable."; return false }
        // Finish admitted writes before deletion; a late save cannot resurrect a deleted record.
        await saveWork?.value
        pendingSaves = pendingSaves.filter { $0.value.canonicalScene.sessionID != id }
        failedSaves = failedSaves.filter { $0.value.canonicalScene.sessionID != id }
        do {
            if let ownedHistoryID {
                // The sidebar carries the exact app-issued record UUID. Safe
                // deletion does not require decoding possibly corrupt contents.
                do { try await store.delete(id: ownedHistoryID) }
                catch ExplanationHistoryStore.StoreError.notFound { /* Exact typed absence is already deleted. */ }
                savedCheckpoints[ownedHistoryID] = nil; linkedHistoryIDs.remove(ownedHistoryID)
            }
            let list: ExplanationHistoryStore.Listing
            do { list = try await store.list() }
            catch ExplanationHistoryStore.StoreError.notFound { return true }
            for record in list.records where record.sessionID == id {
                do { try await store.delete(id: record.id) }
                catch ExplanationHistoryStore.StoreError.notFound { /* Retention may already have removed it. */ }
                savedCheckpoints[record.id] = nil
            }
            if ownedHistoryID == nil, !list.failures.isEmpty {
                saveProblem = "Deletion could not be verified because some history records are unreadable."
                return false
            }
            return true
        } catch {
            saveProblem = "Some linked explanation history could not be deleted. The storage error needs attention."
            return false
        }
    }

    private func updatePhase() {
        switch playback?.state {
        case .playing: phase = .speaking
        case .paused: phase = .paused
        case .awaitingCaptionAdvance: phase = .captions
        case .completed:
            phase = isReceiving ? .thinking : .completed
            if !isReceiving, activePointing != nil {
                activePointing = nil; desktopCard.beginLinger(); onTurnEnded?(nil)
            }
            if !isReceiving, ownsAudio { ownsAudio = false; releaseAudio() }
            if !isReceiving, let diagnosticTurn {
                sampleDiagnosticResources()
                diagnostics.endTurn(diagnosticTurn); self.diagnosticTurn = nil
            }
        case .buffering, .awaitingStart: phase = .preparingSpeech
        case .failed: phase = .idle
        default: if !isReceiving { phase = .idle }
        }
    }
    private func fail(_ error: Error) {
        if let diagnosticTurn {
            let category: ExplanationDiagnostics.Failure = error is ExplanationProviderError ? .provider
                : error is ExplanationAudioError ? .audio : .invalidEvent
            diagnostics.recordFailure(category, for: diagnosticTurn)
        }
        stop()
        if let provider = error as? ExplanationProviderError { problem = provider.localizedDescription }
        else if error is ExplanationAudioError { problem = "Narration is unavailable. Switch to Captions and try again." }
        else { problem = "The explanation stopped because its response was incomplete or invalid. Your committed scene is retained." }
        onTurnEnded?(error)
    }
    private func releaseCapacity(throwing error: Error? = nil) {
        let continuation = capacity; capacity = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    private func queueSave() {
        guard let history, history.revision > 0 || !history.messages.isEmpty else { return }
        if linkedHistoryIDs.insert(history.id).inserted { onSubmission?(history.title) }
        guard store != nil else { return }
        guard savedCheckpoints[history.id] != history.lastCheckpointID else {
            if let failed = failedSaves[history.id], failed.checkpoints.last!.ordinal <= history.checkpoints.last!.ordinal {
                failedSaves[history.id] = nil
            }
            return
        }
        if let savingSnapshot, savingSnapshot.id == history.id,
           savingSnapshot.checkpoints.last!.ordinal >= history.checkpoints.last!.ordinal { return }
        pendingSaves[history.id] = history
        startSaveWorker()
    }
    private func startSaveWorker() {
        guard let store, !pendingSaves.isEmpty else { return }
        guard saveWork == nil else { return }
        saveWork = Task { [weak self] in
            guard let self else { return }
            // Coalesce rapid cues; the serial worker retains per-record compare-and-swap receipts.
            try? await Task.sleep(for: .milliseconds(250))
            while let snapshot = self.pendingSaves.values.first {
                self.pendingSaves[snapshot.id] = nil
                self.savingSnapshot = snapshot
                do {
                    let expected: ExplanationHistoryStore.SaveExpectation = self.savedCheckpoints[snapshot.id].map { .checkpoint($0) } ?? .absent
                    let receipt = try await store.save(snapshot, expecting: expected)
                    self.savedCheckpoints[snapshot.id] = receipt.checkpointID
                    for deletedID in receipt.retention.deletedIDs { self.savedCheckpoints[deletedID] = nil }
                    if let failed = self.failedSaves[snapshot.id], failed.checkpoints.last!.ordinal <= snapshot.checkpoints.last!.ordinal {
                        self.failedSaves[snapshot.id] = nil
                    }
                    if !self.failedSaves.isEmpty {
                        self.saveProblem = "Some explanations are still unsaved. Retry saving before quitting."
                    } else {
                        self.saveProblem = receipt.warnings.isEmpty && receipt.retention.failures.isEmpty
                            ? nil : "The explanation was saved, but storage durability or retention needs attention."
                    }
                } catch {
                    self.failedSaves[snapshot.id] = snapshot
                    self.saveProblem = "An explanation could not be saved. It is retained in memory; retry saving before quitting."
                }
                self.savingSnapshot = nil
            }
            self.saveWork = nil
        }
    }
}
