import Foundation
import ZeusCore

/// How the bridge talks back. `ScribeTranscriber` has no back-channel, so the controller hands these in.
/// All of them may be called from any thread; the controller hops to the main actor.
struct ScribeTranscriberCallbacks: Sendable {
    /// A provisional or final segment. The final one for a chunk replaces its provisional one.
    var onSegment: @Sendable (ScribeTranscriptSegment) -> Void
    /// Every chunk has been recognised (or failed): the transcript is complete.
    var onFinished: @Sendable (ScribeSessionID) -> Void
    /// Something went wrong that the person should know about (a chunk couldn't be recognised).
    var onIssue: @Sendable (String) -> Void = { _ in }
    /// How loud a source's newest gated audio is (0...1), at most about 20 times a second per source.
    var onLevel: @Sendable (ScribeAudioSource, Double) -> Void = { _, _ in }
    /// Every closed turn's voice, said once, just before `onFinished`. Memory only: it feeds the post-meeting
    /// speaker correction and "Remember this voice", and is never written to disk.
    var onTurns: @Sendable ([ScribeTurnEmbedding]) -> Void = { _ in }
}

/// What the recogniser needs to tell voices apart, ready before the first chunk: a trained embedder when its
/// model is on disk (else nil, and the hand-built voiceprint is used) and the voices the owner chose to remember.
struct ScribeSpeakerSetup: Sendable {
    var embedder: FluidVoiceEmbedder?
    var library = ScribeVoiceLibrary()

    /// The shipped app: the model if downloaded, and the saved voices if the file reads.
    static func live() async -> ScribeSpeakerSetup {
        let embedder = await SpeakerModelStore.loadEmbedder()
        let library = (try? ScribeVoiceLibraryStore.standard.load()) ?? ScribeVoiceLibrary()
        return ScribeSpeakerSetup(embedder: embedder, library: library)
    }
}

/// Cuts each source's gated frames into speaker turns (a pause closes one, 8 s at most) and recognises them
/// one at a time. While a turn is still being spoken, an on-device engine also reads the audio so far every
/// ~1.2 s, so the page can show provisional text long before the turn closes.
/// One bridge serves one session. Frames arrive on the capture worker queue; recognition runs on one
/// background task. Pending chunks are bounded per source: when recognition falls behind, the oldest pending
/// chunk is dropped and counted, `onIssue` says so, and capture is never blocked.
final class ScribeTranscriberBridge: ScribeTranscriber, @unchecked Sendable {
    typealias Transcribe = @Sendable ([Float]) async throws -> String
    /// A rolling preview read. It must be local-only (see `ScribeEngineHub.transcribePreview`); nil means
    /// "no preview", whether nothing was heard, no on-device engine is ready or the read failed.
    typealias TranscribePreview = @Sendable ([Float]) async -> String?

    static let maxPendingChunksPerSource = 4
    static let overloadMessage = "Transcription is behind, so some audio wasn't transcribed."
    /// Audio seconds between two preview reads of the same source.
    static let previewInterval: TimeInterval = 1.2
    /// Wall-clock seconds one preview read may take before it is abandoned; finals never wait for it.
    static let previewBudget: TimeInterval = 4
    /// Audio seconds between two level reports of the same source (about 20 a second).
    static let levelInterval: TimeInterval = 0.05

    /// The bounded per-source queues, shared by the producer (`ingest`) and the recognition task.
    private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var mic = ScribeBoundedQueue<ScribeChunk>(capacity: ScribeTranscriberBridge.maxPendingChunksPerSource)
        private var system = ScribeBoundedQueue<ScribeChunk>(capacity: ScribeTranscriberBridge.maxPendingChunksPerSource)
        /// One slot per source, newest wins: previews never queue up behind each other.
        private var micPreview: ScribeChunkPreview?
        private var systemPreview: ScribeChunkPreview?
        private var micPreviewBusy = false
        private var systemPreviewBusy = false
        private var finishing = false

        /// True when an older pending chunk was dropped to make room. A closed chunk makes that source's
        /// waiting preview stale, so it is withdrawn.
        func push(_ source: ScribeAudioSource, _ chunk: ScribeChunk) -> Bool {
            lock.withLock {
                switch source {
                case .microphone:
                    micPreview = nil
                    return mic.push(chunk) != nil
                case .system:
                    systemPreview = nil
                    return system.push(chunk) != nil
                }
            }
        }

        /// The older of the two queue heads, so sources stay roughly in meeting order.
        func pop() -> (ScribeAudioSource, ScribeChunk)? {
            lock.withLock {
                switch (mic.first, system.first) {
                case (nil, nil): return nil
                case (let m?, nil): _ = mic.pop(); return (.microphone, m)
                case (nil, let s?): _ = system.pop(); return (.system, s)
                case (let m?, let s?):
                    if m.start <= s.start { _ = mic.pop(); return (.microphone, m) }
                    _ = system.pop()
                    return (.system, s)
                }
            }
        }

        /// Offers the newest in-progress audio of a source for a preview. Refused while that source has a final
        /// chunk waiting, a preview waiting or running, or the session is finishing.
        func offerPreview(_ source: ScribeAudioSource, _ preview: ScribeChunkPreview) -> Bool {
            lock.withLock { () -> Bool in
                guard !finishing else { return false }
                switch source {
                case .microphone:
                    guard micPreview == nil, !micPreviewBusy, mic.isEmpty else { return false }
                    micPreview = preview
                case .system:
                    guard systemPreview == nil, !systemPreviewBusy, system.isEmpty else { return false }
                    systemPreview = preview
                }
                return true
            }
        }

        /// The older waiting preview; its source stays busy until `previewDone`.
        func popPreview() -> (ScribeAudioSource, ScribeChunkPreview)? {
            lock.withLock { () -> (ScribeAudioSource, ScribeChunkPreview)? in
                guard !finishing else { return nil }
                switch (micPreview, systemPreview) {
                case (nil, nil): return nil
                case (let m?, nil):
                    micPreview = nil
                    micPreviewBusy = true
                    return (.microphone, m)
                case (nil, let s?):
                    systemPreview = nil
                    systemPreviewBusy = true
                    return (.system, s)
                case (let m?, let s?):
                    if m.start <= s.start {
                        micPreview = nil
                        micPreviewBusy = true
                        return (.microphone, m)
                    }
                    systemPreview = nil
                    systemPreviewBusy = true
                    return (.system, s)
                }
            }
        }

        func previewDone(_ source: ScribeAudioSource) {
            lock.withLock {
                switch source {
                case .microphone: micPreviewBusy = false
                case .system: systemPreviewBusy = false
                }
            }
        }

        func markFinishing() {
            lock.withLock {
                finishing = true
                micPreview = nil
                systemPreview = nil
            }
        }

        var isDrainedAndFinishing: Bool { lock.withLock { finishing && mic.isEmpty && system.isEmpty } }

        func clear() {
            lock.withLock {
                mic.removeAll()
                system.removeAll()
                micPreview = nil
                systemPreview = nil
            }
        }
    }

    /// Shared with the consumer task so `cancel()` can silence it.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    /// One source's chunker and the pacing of its previews and level reports (all in audio time).
    private struct SourceState {
        var chunker = ScribeChunker()
        var lastPreviewAt = -TimeInterval.infinity
        var lastLevelAt = -TimeInterval.infinity
        var levelPeak = 0.0

        mutating func ingest(_ samples: [Float], at time: TimeInterval) -> Ingested {
            var result = Ingested()
            result.chunks = chunker.append(samples, at: time)
            levelPeak = max(levelPeak, ScribeLevelMeter.level(samples))
            let sinceLevel = time - lastLevelAt
            if sinceLevel >= ScribeTranscriberBridge.levelInterval || sinceLevel < 0 {
                lastLevelAt = time
                result.level = levelPeak
                levelPeak = 0
            }
            let sincePreview = time - lastPreviewAt
            if result.chunks.isEmpty, sincePreview >= ScribeTranscriberBridge.previewInterval || sincePreview < 0,
               let preview = chunker.preview() {
                lastPreviewAt = time
                result.preview = preview
            }
            return result
        }
    }

    /// What one frame produced.
    private struct Ingested {
        var chunks: [ScribeChunk] = []
        var preview: ScribeChunkPreview?
        var level: Double?
    }

    /// Who is speaking, kept on the recognition task. A closed chunk's speaker comes from the diarizer (which
    /// learns from it); a preview is only classified against the voices already known, and shows the source's
    /// neutral label when it matches none, so a new speaker is never labelled as the previous one.
    /// With a trained embedder the diarizer clusters its vectors and starts with the saved voices; without one
    /// it clusters the hand-built voiceprint, exactly as before the model existed.
    private struct Speakers {
        private var diarizer = ScribeDiarizer()
        private var embedder: (any ScribeVoiceEmbedder)?

        init(setup: ScribeSpeakerSetup = ScribeSpeakerSetup()) {
            embedder = setup.embedder
            if let embedder {
                for seed in setup.library.seeds(kind: embedder.kind) { diarizer.seed(name: seed.name, embedding: seed.embedding) }
            }
        }

        private func embedding(for samples: [Float]) -> ScribeVoiceEmbedding? {
            (embedder ?? ScribeHandBuiltEmbedder()).embedding(samples: samples)
        }

        /// The speaker and the voice that decided it (nil when the chunk was too short or had no speech).
        mutating func assign(source: ScribeAudioSource, samples: [Float]) -> (speaker: ScribeSpeaker, voice: ScribeVoiceEmbedding?) {
            let voice = embedding(for: samples)
            return (diarizer.assign(source: source, embedding: voice), voice)
        }

        func provisional(source: ScribeAudioSource, samples: [Float]) -> ScribeSpeaker {
            if let known = diarizer.classify(source: source, embedding: embedding(for: samples)) { return known }
            // An unmatched microphone voice may be someone else in the room: never call it "You" until the
            // final read assigns a label.
            return source == .microphone ? .unknown : ScribeLiveSpeakers.speaker(for: source)
        }
    }

    /// What the closed-chunk task and the preview task share: the speaker memory and the ids that already show
    /// preview text. One lock; every call is short. The trained embedder is not thread-safe, so every use of it
    /// is inside this lock.
    private final class Recogniser: @unchecked Sendable {
        /// Turns kept for the post-meeting pass; more than the pass accepts is pointless.
        private static let turnCap = 1_200
        private let lock = NSLock()
        private var speakers = Speakers()
        private var turns: [ScribeTurnEmbedding] = []
        /// Segment ids that already show preview text, so the "…" placeholder doesn't blank it.
        private var previewed: Set<String> = []

        func install(_ setup: ScribeSpeakerSetup) {
            lock.withLock { speakers = Speakers(setup: setup) }
        }

        func assign(id: String, source: ScribeAudioSource, samples: [Float], duration: TimeInterval) -> ScribeSpeaker {
            lock.withLock {
                let result = speakers.assign(source: source, samples: samples)
                if let voice = result.voice {
                    turns.append(ScribeTurnEmbedding(segmentID: id, source: source, embedding: voice, duration: duration))
                    if turns.count > Self.turnCap { turns.removeFirst(turns.count - Self.turnCap) }
                }
                return result.speaker
            }
        }

        func takeTurns() -> [ScribeTurnEmbedding] {
            lock.withLock {
                defer { turns = [] }
                return turns
            }
        }

        func provisional(source: ScribeAudioSource, samples: [Float]) -> ScribeSpeaker {
            lock.withLock { speakers.provisional(source: source, samples: samples) }
        }

        func notePreviewed(_ id: String) { lock.withLock { _ = previewed.insert(id) } }
        func hasPreview(_ id: String) -> Bool { lock.withLock { previewed.contains(id) } }
        func forget(_ id: String) { lock.withLock { _ = previewed.remove(id) } }
    }

    /// One budgeted preview read: resolves with the first of the read's result, the time budget, or a cancel.
    /// The read itself runs on its own task, so an engine that ignores cancellation is simply abandoned.
    private final class PreviewRace: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?
        private var tasks: [Task<Void, Never>] = []
        private var done = false

        func install(_ continuation: CheckedContinuation<String?, Never>) {
            let already = lock.withLock { () -> Bool in
                if !done { self.continuation = continuation }
                return done
            }
            if already { continuation.resume(returning: nil) }
        }

        func attach(_ tasks: [Task<Void, Never>]) {
            let already = lock.withLock { () -> Bool in
                if !done { self.tasks = tasks }
                return done
            }
            if already { for task in tasks { task.cancel() } }
        }

        func finish(_ value: String?) {
            let (continuation, tasks) = lock.withLock { () -> (CheckedContinuation<String?, Never>?, [Task<Void, Never>]) in
                guard !done else { return (nil, []) }
                done = true
                let taken = (self.continuation, self.tasks)
                self.continuation = nil
                self.tasks = []
                return taken
            }
            continuation?.resume(returning: value)
            for task in tasks { task.cancel() }
        }
    }

    /// The preview read now running, so a closed chunk or the end of the session can cancel it.
    private final class PreviewRun: @unchecked Sendable {
        private let lock = NSLock()
        private var race: PreviewRace?
        private var source: ScribeAudioSource?

        func begin(_ source: ScribeAudioSource, _ race: PreviewRace) {
            lock.withLock {
                self.source = source
                self.race = race
            }
        }

        func end() {
            lock.withLock {
                race = nil
                source = nil
            }
        }

        /// Cancels the running read: any source's, or only `only`'s.
        func cancel(only: ScribeAudioSource? = nil) {
            let target = lock.withLock { () -> PreviewRace? in
                guard let current = self.race else { return nil }
                if let only, self.source != only { return nil }
                return current
            }
            target?.finish(nil)
        }
    }

    /// Reads a preview within `budget` seconds; nil when it is late, cancelled or heard nothing.
    private static func budgetedPreview(
        _ samples: [Float],
        source: ScribeAudioSource,
        run: PreviewRun,
        read: @escaping TranscribePreview
    ) async -> String? {
        let race = PreviewRace()
        run.begin(source, race)
        defer { run.end() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                race.install(continuation)
                let work = Task.detached(priority: .utility) {
                    race.finish(await read(samples))
                }
                let timer = Task.detached(priority: .utility) {
                    try? await Task.sleep(nanoseconds: UInt64(ScribeTranscriberBridge.previewBudget * 1_000_000_000))
                    race.finish(nil)
                }
                race.attach([work, timer])
            }
        } onCancel: {
            race.finish(nil)
        }
    }

    private let session: ScribeSessionID
    private let lock = NSLock()
    private var micState = SourceState()
    private var systemState = SourceState()
    private var finishing = false
    private let pending = Pending()
    private let callbacks: ScribeTranscriberCallbacks
    /// A doorbell, not a queue: it only says "look at `pending`", so it can't grow.
    private let bell: AsyncStream<Void>.Continuation
    /// The same for the preview task, which runs apart from the closed-chunk task.
    private let previewBell: AsyncStream<Void>.Continuation
    private let previewRun = PreviewRun()
    private let cancelled = Flag()

    init(
        session: ScribeSessionID,
        callbacks: ScribeTranscriberCallbacks,
        transcribe: Transcribe? = nil,
        transcribePreview: TranscribePreview? = nil,
        speakerSetup: (@Sendable () async -> ScribeSpeakerSetup)? = nil
    ) {
        self.session = session
        self.callbacks = callbacks
        // The shipped app passes neither: closed chunks use the dictation routing, previews the local-only
        // operation. A caller that injects its own `transcribe` gets previews only if it injects those too.
        let readClosed: Transcribe = transcribe ?? { try await ScribeEngineHub.shared.transcribe($0) }
        let readPreview: TranscribePreview?
        if let transcribePreview {
            readPreview = transcribePreview
        } else if transcribe == nil {
            readPreview = { await ScribeEngineHub.shared.transcribePreview($0) }
        } else {
            readPreview = nil
        }
        let (stream, bell) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.bell = bell
        let (previewStream, previewBell) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.previewBell = previewBell
        let cancelled = self.cancelled
        let pending = self.pending
        let previewRun = self.previewRun
        let state = Recogniser()
        // A caller that injects its own `transcribe` (tests) gets the hand-built voiceprint and no saved voices:
        // no model load and no read of the owner's voice file.
        let prepareSpeakers: @Sendable () async -> ScribeSpeakerSetup
        if let speakerSetup {
            prepareSpeakers = speakerSetup
        } else if transcribe == nil {
            prepareSpeakers = { await ScribeSpeakerSetup.live() }
        } else {
            prepareSpeakers = { ScribeSpeakerSetup() }
        }
        // Closed chunks: only they decide when the transcript is complete, and nothing a preview does can delay them.
        Task.detached(priority: .utility) {
            // Loaded from disk only (never downloaded here); chunks wait in their bounded queue meanwhile.
            state.install(await prepareSpeakers())
            for await _ in stream {
                while !cancelled.isSet, let (source, chunk) = pending.pop() {
                    await Self.recognise(source: source, chunk: chunk, session: session, callbacks: callbacks,
                                         transcribe: readClosed, cancelled: cancelled, state: state)
                }
                if cancelled.isSet { break }
                if pending.isDrainedAndFinishing {
                    callbacks.onTurns(state.takeTurns())
                    callbacks.onFinished(session)
                    break
                }
            }
        }
        // Previews: lowest priority, one at a time, each within its budget, dropped the moment a chunk closes.
        Task.detached(priority: .background) {
            for await _ in previewStream {
                while !cancelled.isSet, let (source, preview) = pending.popPreview() {
                    await Self.recognisePreview(source: source, preview: preview, session: session, callbacks: callbacks,
                                                transcribePreview: readPreview, run: previewRun,
                                                cancelled: cancelled, state: state)
                    pending.previewDone(source)
                }
            }
        }
    }

    deinit {
        bell.finish()
        previewBell.finish()
    }

    func ingest(_ frame: ScribeAudioFrame) {
        guard frame.session == session else { return }
        let samples = ScribePCM.decode(frame.payload)
        guard !samples.isEmpty else { return }
        let source = frame.source
        let result = lock.withLock { () -> Ingested in
            guard !finishing else { return Ingested() }
            switch source {
            case .microphone: return micState.ingest(samples, at: frame.hostTime)
            case .system: return systemState.ingest(samples, at: frame.hostTime)
            }
        }
        if let level = result.level { callbacks.onLevel(source, level) }
        enqueue(result.chunks.map { (source, $0) })
        if let preview = result.preview, pending.offerPreview(source, preview) { previewBell.yield() }
    }

    /// Flushes both sources, recognises what is left, then reports `onFinished`. Idempotent.
    func finish(session finished: ScribeSessionID) {
        guard finished == session else { return }
        let flushed = lock.withLock { () -> [(ScribeAudioSource, ScribeChunk)]? in
            guard !finishing else { return nil }
            finishing = true
            var chunks: [(ScribeAudioSource, ScribeChunk)] = []
            if let chunk = micState.chunker.flush() { chunks.append((.microphone, chunk)) }
            if let chunk = systemState.chunker.flush() { chunks.append((.system, chunk)) }
            return chunks
        }
        guard let flushed else { return }
        enqueue(flushed)
        pending.markFinishing()
        // Finishing never waits for a preview: the running one is dropped and the preview task ends.
        previewRun.cancel()
        previewBell.finish()
        bell.yield()
    }

    /// The session failed or was cancelled: stop recognising and report nothing more.
    func cancel() {
        cancelled.set()
        pending.clear()
        previewRun.cancel()
        previewBell.finish()
        bell.finish()
    }

    /// Never blocks: a full queue drops its oldest chunk and the person is told once per drop. A silent chunk
    /// (a dead input or a quiet room) is rejected first: it has nothing to recognise, and it must not push real
    /// speech out of the bounded queue. Its index stays used, so later chunks keep their ids.
    private func enqueue(_ chunks: [(ScribeAudioSource, ScribeChunk)]) {
        let audible = chunks.filter { !ScribeAudioMath.isSilent($0.1.samples) }
        var dropped = false
        for (source, chunk) in audible {
            if pending.push(source, chunk) { dropped = true }
            // The turn closed: a preview of it is stale and must not hold up anything.
            previewRun.cancel(only: source)
        }
        if dropped { callbacks.onIssue(Self.overloadMessage) }
        if !audible.isEmpty { bell.yield() }
    }

    private static func recognise(
        source: ScribeAudioSource,
        chunk: ScribeChunk,
        session: ScribeSessionID,
        callbacks: ScribeTranscriberCallbacks,
        transcribe: Transcribe,
        cancelled: Flag,
        state: Recogniser
    ) async {
        // A dead input or a quiet room: nothing to recognise, and nothing to show.
        guard !ScribeAudioMath.isSilent(chunk.samples) else { return }
        let id = ScribeLiveSpeakers.segmentID(source: source, chunkIndex: chunk.index)
        let speaker = state.assign(id: id, source: source, samples: chunk.samples, duration: chunk.duration)
        func segment(_ text: String, isFinal: Bool) -> ScribeTranscriptSegment {
            ScribeTranscriptSegment(
                id: id, session: session, speaker: speaker,
                start: chunk.start, end: chunk.start + chunk.duration,
                text: text, isFinal: isFinal
            )
        }
        // A readable preview is already on screen for this turn: don't blank it with a placeholder.
        if !state.hasPreview(id) { callbacks.onSegment(segment("…", isFinal: false)) }
        defer { state.forget(id) }
        do {
            let text = try await transcribe(chunk.samples).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cancelled.isSet else { return }
            callbacks.onSegment(segment(text, isFinal: true))
        } catch {
            guard !cancelled.isSet else { return }
            // Never promoted to final: unconfirmed output must not reach the notes.
            callbacks.onSegment(segment("(couldn't transcribe this part)", isFinal: false))
            callbacks.onIssue("Couldn't transcribe part of the meeting: \(error.localizedDescription)")
        }
    }

    /// Reads the turn so far and shows it as provisional text under the id its final segment will have.
    /// A preview that fails or hears nothing is skipped quietly: the final read reports real problems.
    private static func recognisePreview(
        source: ScribeAudioSource,
        preview: ScribeChunkPreview,
        session: ScribeSessionID,
        callbacks: ScribeTranscriberCallbacks,
        transcribePreview: TranscribePreview?,
        run: PreviewRun,
        cancelled: Flag,
        state: Recogniser
    ) async {
        guard let transcribePreview, !ScribeAudioMath.isSilent(preview.samples) else { return }
        guard let raw = await budgetedPreview(preview.samples, source: source, run: run, read: transcribePreview) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cancelled.isSet, !text.isEmpty else { return }
        let id = ScribeLiveSpeakers.segmentID(source: source, chunkIndex: preview.index)
        state.notePreviewed(id)
        callbacks.onSegment(ScribeTranscriptSegment(
            id: id, session: session, speaker: state.provisional(source: source, samples: preview.samples),
            start: preview.start, end: preview.start + preview.duration,
            text: text, isFinal: false
        ))
    }
}

/// Builds the speech router once, from the same engines and the same preference as dictation: the engine the
/// person chose in Dictation settings when it is ready, otherwise the first ready on-device engine (Apple last).
/// A cloud engine is used only when that is what the person chose; it is never a fallback.
actor ScribeEngineHub {
    static let shared = ScribeEngineHub()

    private var router: TranscriptionRouter?

    func transcribe(_ samples: [Float]) async throws -> String {
        let preferred = await MainActor.run { DictationSettings.shared.engine }
        let router = await currentRouter()
        let transcript = try await router.transcribe(samples: samples, preferred: preferred)
        return transcript.text
    }

    /// A rolling preview: reads the audio with one on-device engine, chosen once for this request, and with
    /// nothing else. It never goes through the router, so no fallback and no later read of the dictation
    /// preference can send it to a cloud engine. Nil when no on-device engine is ready or the read fails.
    func transcribePreview(_ samples: [Float]) async -> String? {
        let preferred = await MainActor.run { DictationSettings.shared.engine }
        let router = await currentRouter()
        let states = await router.availability()
        guard let kind = ScribePreviewEngine.pick(preferred: preferred, availability: states),
              !kind.isCloud, let engine = router.engines[kind] else { return nil }
        return try? await engine.transcribe(samples: samples, hints: [], language: nil)
    }

    private func currentRouter() async -> TranscriptionRouter {
        if let existing = router { return existing }
        let made = await MainActor.run { Self.makeRouter() }
        // Another call may have built one while this one waited on the main actor: keep the first.
        if let existing = router { return existing }
        router = made
        return made
    }

    @MainActor
    private static func makeRouter() -> TranscriptionRouter {
        let engines: [any TranscriptionEngine] = [
            ParakeetEngine(),
            ParakeetEngine(.parakeetUltra),
            WhisperKitEngine(),
            WhisperCppEngine(),
            AppleAnalyzerEngine(),
            AppleSpeechEngine(),
            FasterWhisperEngine(),
            ElevenLabsScribeEngine(),
            OpenAITranscribeEngine(),
        ]
        return TranscriptionRouter(engines: engines)
    }
}
