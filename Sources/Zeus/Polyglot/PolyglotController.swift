import AppKit
import Observation
import Speech
import SwiftUI
import Translation
import ZeusCore

/// Live translated captions: microphone, Mac audio or both in, detected language and the target
/// language out. Ideas (the three-input source model, the caption card with source and
/// translation lines, the edge strip, the silence-hallucination filter) come from the original Polyglot project; the engine here is native: Zeus's speech engines, the system's
/// language recognizer and Apple's Translation framework.
@MainActor
@Observable
final class PolyglotController {
    private enum AudioInput: Sendable {
        case samples(PolyglotSide, [Float])
        case clear(Int)
    }
    static let shared = PolyglotController()

    let settings = PolyglotSettings.shared

    // What the card shows.
    private(set) var isListening = false
    private(set) var isStarting = false
    private(set) var transcript = PolyglotTranscript()
    /// The line being said per input; only the current utterance's partial is ever kept.
    private(set) var live = PolyglotLivePartials()
    var partials: [PolyglotSide: String] { live.texts }
    private(set) var detectedLanguage: String?
    private(set) var level: Double = 0
    private(set) var notice: String?
    private(set) var engineName = ""
    /// A language pack is missing for this pair: the card offers to download it.
    private(set) var packNeeded: (source: String, target: String)?
    /// The person tapped "Download" and macOS has not answered yet.
    private(set) var isDownloadingPack = false
    private(set) var permissionPane: String?
    private(set) var isPoppedOut = false
    /// Keeps the Polyglot notch page visible; Stop and explicit dismissal remain independent.
    private(set) var isPinned = false
    /// Set when the person taps "Download": the SwiftUI translation task hosted by the page reads it.
    private(set) var packConfiguration: Any?
    /// The source of the current run (the setting can change while listening; it applies at the next start).
    private(set) var activeSource: PolyglotSource = .microphone

    @ObservationIgnored private var mic: PolyglotMicCapture?
    @ObservationIgnored private var system: PolyglotSystemCapture?
    @ObservationIgnored private var pipeline: PolyglotPipeline?
    @ObservationIgnored private var audioTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var audioIn: AsyncStream<AudioInput>.Continuation?
    @ObservationIgnored private var eventIn: AsyncStream<PolyglotEvent>.Continuation?
    @ObservationIgnored private var panel: PolyglotCaptionPanel?
    @ObservationIgnored private let translator = PolyglotAppleTranslator()
    @ObservationIgnored private let parakeet = ParakeetEngine()
    @ObservationIgnored private let hotkeyMonitor = HotkeyMonitor()
    @ObservationIgnored private var lastLevelAt = Date.distantPast
    /// Bumped by every start and stop; a start whose token no longer matches is abandoned and torn down.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// Bumped when a run's pipeline is created; events from an older run's draining stream are dropped.
    @ObservationIgnored private var epoch = 0
    /// Clear drops what is still draining: events from runs older than this never land again.
    @ObservationIgnored private var clearedBelow = 0
    @ObservationIgnored private var translationRevision = 0
    @ObservationIgnored private var targetSelectionRevision = 0
    @ObservationIgnored private var clearSequence = 0
    @ObservationIgnored private var pendingClear: (epoch: Int, token: Int)?
    @ObservationIgnored private var hotkeyInstalled = false
    /// Told when something Zeus should say in the notch happens (a missing permission, a missing pack).
    @ObservationIgnored var onHint: (String) -> Void = { _ in }

    private init() {
        PolyglotCaptionBridge.shared = self
        settings.onTargetChange = { [weak self] target in
            guard let self else { return }
            // Clear the old destination immediately, before any suspended translation can return.
            self.translationRevision += 1
            self.targetSelectionRevision += 1
            let revision = self.translationRevision
            self.packNeeded = nil
            self.notice = nil
            self.transcript.retarget(to: target)
            let pipeline = self.pipeline
            Task {
                guard revision == self.translationRevision else { return }
                await pipeline?.setTarget(target, request: revision)
                guard revision == self.translationRevision else { return }
                await self.retranslateWaiting()
            }
        }
        settings.onEnabledChange = { [weak self] enabled in
            guard !enabled else { return }
            // Turned off in Settings: nothing may keep listening or stay on screen.
            self?.stop()
            self?.isPinned = false
            NotchControllerBridge.controller?.polyglotPinChanged()
            self?.closePopOut()
        }
    }

    // MARK: Hotkey

    func installHotkey() {
        guard !hotkeyInstalled else { return }
        hotkeyInstalled = true
        hotkeyMonitor.role = .dictation
        hotkeyMonitor.keyProvider = { [settings] in settings.enabled ? settings.hotkey : nil }
        hotkeyMonitor.sharedProvider = { false }
        hotkeyMonitor.directPressProvider = { true }
        hotkeyMonitor.onPress = { [weak self] in self?.toggle() }
        hotkeyMonitor.start()
    }

    // MARK: Start and stop

    func toggle() { isListening || isStarting ? stop() : start() }

    func start(source: PolyglotSource? = nil) {
        guard settings.enabled else {
            onHint("Polyglot is off. Turn it on in Settings, Polyglot.")
            return
        }
        guard !isListening, !isStarting else { return }
        let chosen = source ?? settings.source
        activeSource = chosen
        isStarting = true
        notice = nil
        permissionPane = nil
        packNeeded = nil
        generation += 1
        let token = generation
        // Captions start on the deployment target. On-device translation is checked per language
        // pair and stays unavailable below macOS 26; the heard line is still shown.
        startTask = Task { [weak self] in await self?.begin(chosen, generation: token) }
    }

    func stop() {
        // Invalidate any start still waiting on a prompt or a capture: whatever it finishes is torn down.
        generation += 1
        startTask?.cancel()
        startTask = nil
        isStarting = false
        live.dropPartials()
        let wasLive = isListening || pipeline != nil
        isListening = false
        mic?.stop()
        system?.stop()
        mic = nil
        system = nil
        audioIn?.finish()
        audioIn = nil
        level = 0
        guard wasLive else { return }
        let closing = pipeline
        pipeline = nil
        // Let the last utterance land: the event stream ends only once this run's audio is ingested and its
        // pipeline has finished, however long recognition takes. Only this run's stream is ended: a start
        // that follows keeps its own.
        let ingesting = audioTask
        audioTask = nil
        let eventEnd = eventIn
        eventIn = nil
        eventTask = nil
        Task {
            await ingesting?.value
            await closing?.finish()
            eventEnd?.finish()
        }
    }

    private func isCurrent(_ token: Int) -> Bool { token == generation && !Task.isCancelled }

    private func begin(_ source: PolyglotSource, generation token: Int) async {
        // Engine: Parakeet v3 when it is already on this Mac, Apple's on-device recognizer otherwise.
        let parakeetReady = await parakeet.availability().isReady
        guard isCurrent(token) else { return }
        let recognizer = PolyglotRecognizer(parakeet: parakeet, useParakeet: parakeetReady)
        engineName = recognizer.engineName
        if !parakeetReady {
            await ensureSpeechAuthorization()
            guard isCurrent(token) else { return }
            // Fail closed: never send captions audio to Apple's servers under an on-device label.
            if let problem = PolyglotRecognizer.appleOnDeviceProblem() {
                isStarting = false
                notice = problem
                if SFSpeechRecognizer.authorizationStatus() != .authorized { permissionPane = "Privacy_SpeechRecognition" }
                onHint(problem)
                return
            }
        }

        // Each run numbers its lines in its own block: a run still draining after Stop never collides with the next one.
        let firstLineID = PolyglotRunIDs.firstID(run: epoch + 1)
        let (events, eventContinuation) = AsyncStream.makeStream(of: PolyglotEvent.self)
        let pipeline = PolyglotPipeline(recognizer: recognizer, detector: PolyglotNLDetector(), translator: translator,
                                        target: settings.target, firstID: firstLineID) { eventContinuation.yield($0) }
        let (audio, audioContinuation) = AsyncStream.makeStream(of: AudioInput.self)
        self.pipeline = pipeline
        audioIn = audioContinuation
        eventIn = eventContinuation
        epoch += 1
        pendingClear = nil
        let sessionEpoch = epoch
        let sessionTargetRevision = targetSelectionRevision
        live.reset()
        eventTask = Task { [weak self] in
            await PolyglotEventDrain.consume(events, run: sessionEpoch, targetRevisionAtStart: sessionTargetRevision,
                handle: { [weak self] in self?.handle($0, epoch: sessionEpoch) },
                recoveryState: { [weak self] in
                    guard let self else { return nil }
                    return .init(targetRevision: self.targetSelectionRevision, currentRun: self.epoch,
                                 clearedBelow: self.clearedBelow, clearPending: self.pendingClear != nil)
                },
                recover: { [weak self] ids in await self?.retranslateWaiting(ids: ids) })
        }
        audioTask = Task { [weak self] in
            for await input in audio {
                switch input {
                case .samples(let side, let samples): await pipeline.ingest(samples, from: side)
                case .clear(let token): await pipeline.clear(token: token)
                }
                _ = self
            }
        }

        var problems: [String] = []
        var started = false
        if source.usesMicrophone {
            let capture = PolyglotMicCapture()
            capture.onStopped = { [weak self] message in
                Task { @MainActor in self?.micStopped(message, token: token) }
            }
            do {
                try await capture.start { [weak self] chunk in
                    audioContinuation.yield(.samples(.microphone, chunk.samples))
                    Task { @MainActor in self?.updateLevel(chunk.level) }
                }
                // Stop was pressed while the capture was starting: never leave the mic running.
                guard isCurrent(token) else { capture.stop(); audioContinuation.finish(); return }
                mic = capture
                started = true
            } catch {
                guard isCurrent(token) else { capture.stop(); audioContinuation.finish(); return }
                problems.append(error.localizedDescription)
                if case PolyglotAudioError.microphoneDenied = error { permissionPane = "Privacy_Microphone" }
            }
        }
        if source.usesSystemAudio {
            let capture = PolyglotSystemCapture()
            capture.onStopped = { [weak self] message in
                Task { @MainActor in self?.systemStopped(message, token: token) }
            }
            do {
                try await capture.start { [weak self] chunk in
                    audioContinuation.yield(.samples(.system, chunk.samples))
                    Task { @MainActor in self?.updateLevel(chunk.level) }
                }
                guard isCurrent(token) else {
                    capture.onStopped = nil
                    capture.stop()
                    audioContinuation.finish()
                    return
                }
                system = capture
                started = true
            } catch {
                guard isCurrent(token) else { audioContinuation.finish(); return }
                problems.append(error.localizedDescription)
                if case PolyglotAudioError.screenRecordingDenied = error { permissionPane = "Privacy_ScreenCapture" }
            }
        }
        // The mic may have started before this check: a stop in between has already torn the session down.
        guard isCurrent(token) else {
            mic?.stop(); mic = nil
            system?.stop(); system = nil
            audioContinuation.finish()
            return
        }
        isStarting = false
        startTask = nil
        guard started else {
            notice = problems.joined(separator: " ")
            if let first = problems.first { onHint(first) }
            audioContinuation.finish()
            audioIn = nil
            self.pipeline = nil
            eventIn?.finish()
            eventIn = nil
            eventTask = nil
            return
        }
        isListening = true
        if !problems.isEmpty { notice = problems.joined(separator: " ") }
    }

    private func ensureSpeechAuthorization() async { await SpeechAuthorization.ensure() }

    private func updateLevel(_ value: Double) {
        // A chunk already queued when Stop was pressed must not light the meter again.
        guard isListening || isStarting else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLevelAt) > 0.05 else { return }
        lastLevelAt = now
        level = value
    }

    // MARK: Events

    /// Mac audio ended on its own: drop it, and end the run when it was the only source.
    private func systemStopped(_ message: String, token: Int) {
        guard token == generation else { return }
        system?.onStopped = nil
        system?.stop()
        system = nil
        notice = message
        if mic == nil { stop(); notice = message }
    }

    /// The Mac's microphone changed or went away mid-run: drop it, and end the run when it was the only source.
    private func micStopped(_ message: String, token: Int) {
        guard token == generation else { return }
        mic?.onStopped = nil
        mic?.stop()
        mic = nil
        notice = message
        if system == nil { stop(); notice = message }
    }

    private func handle(_ event: PolyglotEvent, epoch eventEpoch: Int) {
        // A new run has started since this stream began draining: its settled captions still land (ids are
        // unique per run), but its partials and status messages are about a moment that has passed.
        guard eventEpoch == epoch || event.isSettled else { return }
        guard eventEpoch >= clearedBelow else { return }
        if case .cleared(let token) = event {
            if pendingClear?.epoch == eventEpoch, pendingClear?.token == token { pendingClear = nil }
            return
        }
        guard pendingClear == nil else { return }
        switch event {
        case .partial(let side, let id, let text):
            // Partials are only live while listening, and only for the input's current utterance:
            // one for an utterance that already ended (or was superseded) is dropped.
            guard isListening else { return }
            live.applyPartial(side: side, id: id, text: text)
        case .discarded(let side, let id):
            live.settle(side: side, id: id)
        case .line(var line):
            live.settle(side: line.side, id: line.id)
            line.isTarget = line.language.map { PolyglotLanguage.base($0) == PolyglotLanguage.base(settings.target) } ?? false
            transcript.applySettled(.line(line))
            if let language = line.language { detectedLanguage = language }
        case .translated(_, _, let target):
            guard PolyglotLanguage.base(target) == PolyglotLanguage.base(settings.target) else { return }
            transcript.applySettled(event)
        case .needsPack(let source, let target):
            guard PolyglotLanguage.base(target) == PolyglotLanguage.base(settings.target) else { return }
            // Every line of that language raises this again: say it once, not per line.
            let isNew = packNeeded?.source != source || packNeeded?.target != target
            packNeeded = (source, target)
            if isNew { onHint("Polyglot needs the \(PolyglotLanguage.name(for: source)) language pack.") }
        case .failed(let message):
            notice = message
        case .cleared: break // handled before the pending-clear gate
        }
    }

    func clear() {
        // Place Clear in the same queue as audio. Hide old events until that ordered barrier returns.
        // A stopped (draining) run must never bring cleared speech back.
        clearedBelow = pipeline != nil ? epoch : epoch + 1
        translationRevision += 1
        if let audioIn {
            clearSequence += 1
            pendingClear = (epoch, clearSequence)
            audioIn.yield(.clear(clearSequence))
        } else {
            pendingClear = nil
        }
        transcript.clear()
        live.dropPartials()
        detectedLanguage = nil
        notice = nil
        permissionPane = nil
    }

    func copyTranscript() {
        let text = transcript.text(target: settings.target)
        guard !text.isEmpty else { flash("Nothing to copy yet."); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Transcript copied.")
    }

    /// A short confirmation that goes away by itself (errors and permission notices stay).
    private func flash(_ message: String) {
        notice = message
        permissionPane = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.notice == message { self?.notice = nil }
        }
    }

    func openPermissionPane() {
        guard let permissionPane, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permissionPane)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Language packs

    /// Asks macOS to download the pack (its own sheet), then translates what was waiting for it.
    func downloadPack() {
        guard let packNeeded, !isDownloadingPack else { return }
        if #available(macOS 15.0, *) {
            isDownloadingPack = true
            notice = nil
            packConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: packNeeded.source),
                                                                 target: Locale.Language(identifier: packNeeded.target))
        } else {
            notice = "Language packs need macOS 15 or later. Add the pack in System Settings, General, Language & Region, Translation Languages."
        }
    }

    func packFinished(success: Bool, message: String? = nil) {
        packConfiguration = nil
        isDownloadingPack = false
        guard success else {
            notice = message ?? "The language pack did not download. You can add it in System Settings, General, Language & Region, Translation Languages."
            return
        }
        packNeeded = nil
        notice = nil
        Task { await retranslateWaiting() }
    }

    private func retranslateWaiting(ids: Range<Int>? = nil) async {
        let revision = translationRevision
        let target = settings.target
        let waiting = transcript.lines.filter {
            $0.isFinal && !$0.isTarget && $0.translation == nil && $0.language != nil && (ids?.contains($0.id) ?? true)
        }
        let items = waiting.map { (language: $0.language ?? "", request: PolyglotTranslationRequest(id: $0.id, text: $0.original)) }
        for batch in PolyglotBatching.group(items) {
            guard revision == translationRevision else { return }
            let status = await translator.status(from: batch.language, to: target)
            guard revision == translationRevision else { return }
            guard status == .installed else {
                if status == .needsDownload { packNeeded = (batch.language, target) }
                if status == .unsupported {
                    notice = "\(PolyglotLanguage.name(for: batch.language)) to \(PolyglotLanguage.name(for: target)) is not available for translation."
                }
                continue
            }
            let answers: [String]
            do {
                answers = try await translator.translate(batch.requests, from: batch.language, to: target)
            } catch {
                guard revision == translationRevision else { return }
                notice = "Translation failed: \(error.localizedDescription)"
                continue
            }
            guard revision == translationRevision else { return }
            for (request, answer) in zip(batch.requests, answers) where !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcript.setTranslation(id: request.id, answer)
            }
        }
    }

    // MARK: Pop out

    func togglePin() {
        isPinned.toggle()
        NotchControllerBridge.controller?.polyglotPinChanged()
    }

    func togglePopOut() { isPoppedOut ? closePopOut() : popOut() }

    func popOut() {
        guard panel == nil else { return }
        let panel = PolyglotCaptionPanel(polyglot: self)
        panel.onClose = { [weak self] in
            self?.panel = nil
            self?.isPoppedOut = false
        }
        panel.show()
        self.panel = panel
        isPoppedOut = true
    }

    func closePopOut() {
        panel?.close()
        panel = nil
        isPoppedOut = false
    }

    // MARK: Snapshots

    func seedForSnapshot() {
        let now = Date()
        transcript = PolyglotTranscript(lines: [
            PolyglotLine(id: 1, side: .system, original: "Vamos começar a reunião, temos muito para cobrir hoje.", language: "pt",
                         translation: "Let's start the meeting, we have a lot to cover today.", date: now),
            PolyglotLine(id: 2, side: .system, original: "¿Podemos revisar primero el presupuesto del trimestre?", language: "es",
                         translation: "Can we review the quarter's budget first?", date: now),
            PolyglotLine(id: 3, side: .microphone, original: "Sure, I can share my screen in a second.", language: "en", isTarget: true, date: now),
            PolyglotLine(id: 4, side: .system, original: "Oui, et ensuite on parlera du calendrier de livraison.", language: "fr",
                         translation: "Yes, and then we'll talk about the delivery schedule.", date: now),
        ])
        live.applyPartial(side: .system, id: 5, text: "Perfeito, então podemos")
        detectedLanguage = "pt"
        isListening = true
        activeSource = .both
        engineName = "Parakeet v3"
        level = 0.55
    }
}

extension PolyglotController: PolyglotCaptionSharing {
    func applyScreenSharePolicy(visibleInShare: Bool) {
        if let panel {
            ZeusWindowSharing.apply(to: panel, visibleInShare: visibleInShare, surface: .zeusStandard)
        }
    }
}

/// Speech Recognition permission for Apple's recognizer (asked once, when Polyglot first needs it).
enum SpeechAuthorization {
    static func ensure() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await SystemAuthorization.requestSpeechRecognition()
        }
    }
}
