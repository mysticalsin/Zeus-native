import AVFoundation
import Speech
import ZeusCore

/// Microphone → Apple speech recognition (on-device when the language supports it).
/// Free, no API key. Deepgram / AssemblyAI streaming can slot in later behind the same calls.
final class SpeechInput: @unchecked Sendable {
    enum InputError: LocalizedError {
        case recognizerUnavailable
        case onDeviceUnavailable
        case inputUnavailable
        case invalidCapturePolicy
        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                "Speech recognition isn't available for this language right now."
            case .onDeviceUnavailable:
                "On-device speech recognition isn't available for this language. Nothing was recorded. Pick another language or engine, or allow Apple server recognition in settings."
            case .inputUnavailable:
                "The selected microphone is unavailable or has an invalid audio format."
            case .invalidCapturePolicy:
                "The recording limit is invalid."
            }
        }
    }

    // Handlers and flags below are read on the audio and Apple callback threads and written on
    // the main actor, so every access goes through `lock`.
    private var levelHandler: (@Sendable (Double) -> Void)?
    private var partialHandler: (@Sendable (String) -> Void)?
    private var identifiedPartialHandler: (@Sendable (Int, UInt64, String) -> Void)?
    private var samplesHandler: (@Sendable ([Float]) -> Void)?
    private var recognizesFlag = true
    private var serverAllowed = false
    private var captureFailureHandler: (@Sendable (Int, UInt64, CaptureFailure) -> Void)?
    private var configurationObserver: (any NSObjectProtocol)?

    enum CaptureFailure: Equatable, Sendable { case durationLimit, sampleLimit, configurationChanged }
    struct CapturePolicy: Equatable, Sendable {
        var strictDeviceSelection = false
        var maximumSeconds: Double?
        var maximumSamples: Int?
        var cancelOnConfigurationChange = false

        static let explanation = Self(strictDeviceSelection: true, maximumSeconds: 90,
                                      maximumSamples: 90 * 16_000, cancelOnConfigurationChange: true)
        var isValid: Bool {
            (maximumSeconds.map { $0.isFinite && $0 > 0 && $0 <= 90 } ?? true)
                && (maximumSamples.map { $0 > 0 && $0 <= 90 * 16_000 } ?? true)
        }
        func failure(elapsed: Double, storedSamples: Int, incomingSamples: Int) -> CaptureFailure? {
            if let maximumSeconds, !elapsed.isFinite || elapsed >= maximumSeconds { return .durationLimit }
            if let maximumSamples, incomingSamples > maximumSamples - min(storedSamples, maximumSamples) { return .sampleLimit }
            return nil
        }
    }

    var onCaptureFailure: (@Sendable (Int, UInt64, CaptureFailure) -> Void)? {
        get { lock.withLock { captureFailureHandler } }
        set { lock.withLock { captureFailureHandler = newValue } }
    }

    static func validInputFormat(sampleRate: Double, channels: UInt32) -> Bool {
        sampleRate.isFinite && sampleRate >= 8_000 && sampleRate <= 384_000 && channels > 0 && channels <= 32
    }

    /// Mic level 0…1, called on the audio thread.
    var onLevel: (@Sendable (Double) -> Void)? {
        get { lock.withLock { levelHandler } }
        set { lock.withLock { levelHandler = newValue } }
    }
    /// Live transcript while speaking, called off the main thread.
    var onPartial: (@Sendable (String) -> Void)? {
        get { lock.withLock { partialHandler } }
        set { lock.withLock { partialHandler = newValue } }
    }
    /// Same transcript, tagged with the speech session ID and the controller generation that
    /// started the session, so a queued update can be checked when it runs.
    var onIdentifiedPartial: (@Sendable (Int, UInt64, String) -> Void)? {
        get { lock.withLock { identifiedPartialHandler } }
        set { lock.withLock { identifiedPartialHandler = newValue } }
    }
    /// Names and jargon the recognizer should expect (custom vocabulary).
    var contextualStrings: [String] = []
    /// Keep the audio as 16 kHz samples for a local model (dictation).
    var recordsSamples = false
    /// Each converted 16 kHz chunk as it arrives (when `recordsSamples`), for a streaming engine.
    /// Called on the audio thread.
    var onSamples: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { samplesHandler } }
        set { lock.withLock { samplesHandler = newValue } }
    }
    /// Run Apple recognition alongside (live words). Off when only a local model listens.
    var recognizes: Bool {
        get { lock.withLock { recognizesFlag } }
        set { lock.withLock { recognizesFlag = newValue } }
    }
    /// Off by default: Apple recognition must run on this Mac. Only an explicit, separate user
    /// choice may set this, because the audio then goes to Apple's servers.
    var allowServerRecognition: Bool {
        get { lock.withLock { serverAllowed } }
        set { lock.withLock { serverAllowed = newValue } }
    }
    /// Core Audio UID of the microphone to use; nil follows the system input.
    var deviceUID: String?
    /// A chosen device was applied, so dropping the choice must point back at the system input.
    private var usedDevice = false

    // Regression (QA round 9, real E2E): a *second* hold-to-dictate turn in the same app run
    // reliably came back with no speech at all -- `~/Library/Application Support/Zeus/Dictation/
    // history` showed the first turn's audio.wav was ~6 s of real speech, correctly transcribed,
    // but the second turn's was silent/garbage despite `say` genuinely playing through the
    // speakers for the full hold. Root cause: reusing one `AVAudioEngine` across `stop()`/
    // `start()` cycles -- after `engine.stop()`, re-reading `engine.inputNode.outputFormat`
    // and re-installing a tap on the *same* engine is a known-fragile AVAudioEngine pattern;
    // the input node can come back with a stale/invalid format on the next `start()`. A fresh
    // `AVAudioEngine()` per turn (built in `start()`, see below) sidesteps that state machine
    // entirely -- this is Apple's own documented workaround for repeated start/stop engines.
    private var engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finished = false
    private var waiters: [CheckedContinuation<String, Never>] = []
    /// Bumped on every start, so a cancelled task's late callbacks can't end the next turn.
    private var generation = 0
    private var samples: [Float] = []
    private var resampler: AudioSamples.Resampler?
    // Regression (QA round 9, real E2E): a held dictation with a mid-sentence pause ("Meet me at
    // three, no, four pm.", PLAN-QA7's own self-correction example) consistently came back as
    // just "No." -- Apple's on-device recognizer ends a recognition task on its own the moment it
    // decides an utterance is finished (a short word before a pause reads exactly like one), and
    // the old code treated *any* `result.isFinal` as "the turn is over", locking in whatever
    // partial text existed at that moment and leaving the rest of the hold's audio un-transcribed.
    // Fix: track whether the person actually released the key (`stopRequested`); an early
    // `isFinal` while they're still holding it folds the text seen so far into `finalizedText`
    // and opens a fresh request/task to keep listening, so a mid-hold pause never truncates the
    // dictation. Only a real `stop()`/`cancel()` is allowed to end things for good.
    private var finalizedText = ""
    /// The recorder's phase (guarded by `lock`): recording, restarting after an early final or an error,
    /// or stopping. The restart decisions and the bound on error restarts live in `SpeechRecorder`.
    private var recorder = SpeechRecorder.State.idle
    /// No more audio is wanted for the current session. Read and written only while holding `lock`.
    private var stopRequested: Bool {
        get { recorder.isStopping }
        set { if newValue { recorder = SpeechRecorder.reduce(recorder, .stopRequested(session: generation)).0 } }
    }
    // PLAN-QA7 P0 item J (Tony 04:15 BRT, woken by test audio): quiet-hours E2E proves dictation
    // without ever playing a sound. While this is true the live tap's (silent-room) buffers are
    // dropped so they never interleave with `injectFile`'s file-sourced buffers on the same
    // request.
    private var suppressLiveTap = false

    /// Who a recognition task reports for: the session it belongs to and the controller turn
    /// that started that session. Carried through the restart after Apple ends an utterance early.
    struct RecognitionTurn: Equatable, Sendable {
        let sessionID: Int
        let origin: UInt64

        func restarted() -> RecognitionTurn { self }

        func emit(_ text: String, legacy: (@Sendable (String) -> Void)?,
                  identified: (@Sendable (Int, UInt64, String) -> Void)?) {
            legacy?(text)
            identified?(sessionID, origin, text)
        }
    }

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    var localeIdentifier: String { lock.withLock { recognizer?.locale.identifier ?? "en-US" } }

    /// The configured recognizer can run on this Mac without sending audio to Apple.
    var supportsOnDevice: Bool { lock.withLock { recognizer?.supportsOnDeviceRecognition ?? false } }

    /// Selects a locale for the next turn. Explicit selections never silently fall back to English.
    @discardableResult
    func configure(localeIdentifier: String?) -> Bool {
        cancel()
        let targetLocale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        let preferred = SFSpeechRecognizer(locale: targetLocale)
        let configured = localeIdentifier == nil
            ? (preferred ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")))
            : preferred
        lock.withLock { recognizer = configured }
        return configured?.isAvailable == true
    }

    /// Returns the speech session ID of this turn.
    @discardableResult
    func start(controllerGeneration: UInt64 = 0, capturePolicy: CapturePolicy = .init()) throws -> Int {
        guard capturePolicy.isValid else { throw InputError.invalidCapturePolicy }
        let activeRecognizer = lock.withLock { recognizer }
        if recognizes {
            guard let activeRecognizer, activeRecognizer.isAvailable else { throw InputError.recognizerUnavailable }
            guard Self.canRecognize(onDeviceSupported: activeRecognizer.supportsOnDeviceRecognition,
                                    serverAllowed: allowServerRecognition) else { throw InputError.onDeviceUnavailable }
        }
        cancel()
        // Fresh engine every turn (see the stored property's comment): avoids the second-turn
        // silent-audio bug from reusing a stopped engine's input node.
        let engine = AVAudioEngine()
        lock.withLock { self.engine = engine }

        let request = makeRequest(recognizer: activeRecognizer)

        if capturePolicy.strictDeviceSelection {
            guard Microphones.use(uid: deviceUID, on: engine) else { throw InputError.inputUnavailable }
            usedDevice = deviceUID != nil
        } else if deviceUID != nil || usedDevice {
            usedDevice = Microphones.use(uid: deviceUID, on: engine) && deviceUID != nil
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard Self.validInputFormat(sampleRate: format.sampleRate, channels: format.channelCount)
        else { throw InputError.inputUnavailable }
        lock.lock()
        self.request = request
        latest = ""
        finalizedText = ""
        finished = false
        Self.resetLiveTapSuppression(suppress: &suppressLiveTap)
        generation += 1
        recorder = SpeechRecorder.reduce(recorder, .started(session: generation)).0
        samples = []
        resampler = recordsSamples ? AudioSamples.Resampler(from: format) : nil
        let current = generation
        let turnResampler = resampler // A stale tap must never mutate a replacement turn's converter.
        lock.unlock()
        let startedAt = ProcessInfo.processInfo.systemUptime

        if capturePolicy.cancelOnConfigurationChange {
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                guard let self, self.lock.withLock({ self.generation == current && !self.stopRequested }) else { return }
                let handler = self.onCaptureFailure
                self.cancel()
                handler?(current, controllerGeneration, .configurationChanged)
            }
        }

        if recognizes, let activeRecognizer {
            beginRecognition(request: request, recognizer: activeRecognizer,
                             turn: RecognitionTurn(sessionID: current, origin: controllerGeneration))
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            if capturePolicy.maximumSeconds != nil {
                let failure = self.lock.withLock { () -> CaptureFailure? in
                    guard self.generation == current, !self.stopRequested else { return nil }
                    let result = capturePolicy.failure(elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                                                       storedSamples: self.samples.count, incomingSamples: 0)
                    if result != nil { self.stopRequested = true }
                    return result
                }
                if let failure {
                    self.reportCaptureFailure(failure, session: current, origin: controllerGeneration)
                    return
                }
                guard self.lock.withLock({ self.generation == current && !self.stopRequested }) else { return }
            }
            if self.recognizes, !self.lock.withLock({ self.suppressLiveTap }) {
                let currentRequest = self.lock.withLock { self.request }
                currentRequest?.append(buffer)
            }
            if let resampler = turnResampler {
                let converted = resampler.convert(buffer)
                let (admitted, failure) = self.lock.withLock { () -> (Bool, CaptureFailure?) in
                    if capturePolicy.maximumSamples != nil,
                       (self.generation != current || self.stopRequested) { return (false, nil) }
                    let failure = capturePolicy.failure(elapsed: ProcessInfo.processInfo.systemUptime - startedAt,
                                                        storedSamples: self.samples.count, incomingSamples: converted.count)
                    if failure != nil { self.stopRequested = true } else { self.samples += converted }
                    return (failure == nil, failure)
                }
                if let failure {
                    self.reportCaptureFailure(failure, session: current, origin: controllerGeneration)
                    return
                }
                guard admitted else { return }
                if !converted.isEmpty { self.onSamples?(converted) }
            }
            if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                var sum: Float = 0
                for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
                let rms = sqrt(sum / Float(buffer.frameLength))
                self.onLevel?(Double(min(max((rms - 0.008) * 10.2, 0), 1)))
            }
        }
        engine.prepare()
        do { try engine.start() } catch { cancel(); throw error }
        return current
    }

    /// Debug/E2E (`dictate-file`): open Apple on-device recognition on an empty request and feed
    /// audio only through `injectFile`, without starting the mic tap. The live tap was picking up
    /// room noise and mis-transcribing as Portuguese/English garbage while the injected WAV was
    /// ignored (QA7 regression 2026-11-03).
    @discardableResult
    func startInjectOnly(controllerGeneration: UInt64 = 0) throws -> Int {
        let activeRecognizer = lock.withLock { recognizer }
        guard recognizes, let activeRecognizer, activeRecognizer.isAvailable else { throw InputError.recognizerUnavailable }
        guard Self.canRecognize(onDeviceSupported: activeRecognizer.supportsOnDeviceRecognition,
                                serverAllowed: allowServerRecognition) else { throw InputError.onDeviceUnavailable }
        cancel()
        let freshEngine = AVAudioEngine()
        lock.withLock { engine = freshEngine }
        let request = makeRequest(recognizer: activeRecognizer)
        lock.lock()
        self.request = request
        latest = ""
        finalizedText = ""
        finished = false
        suppressLiveTap = true
        generation += 1
        recorder = SpeechRecorder.reduce(recorder, .started(session: generation)).0
        samples = []
        resampler = nil
        let current = generation
        lock.unlock()
        beginRecognition(request: request, recognizer: activeRecognizer,
                         turn: RecognitionTurn(sessionID: current, origin: controllerGeneration))
        return current
    }

    private func makeRequest(recognizer: SFSpeechRecognizer?) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        // Fails closed: `start` already refused a recognizer without on-device support unless
        // the user explicitly allowed server recognition.
        let onDevice = recognizer?.supportsOnDeviceRecognition == true
        request.requiresOnDeviceRecognition = Self.requiresOnDevice(onDeviceSupported: onDevice,
                                                                     serverAllowed: allowServerRecognition)
        return request
    }

    /// Recognition may start when this Mac can do it on-device, or the user chose servers.
    static func canRecognize(onDeviceSupported: Bool, serverAllowed: Bool) -> Bool {
        onDeviceSupported || serverAllowed
    }

    /// On-device is required unless the user explicitly chose server recognition.
    static func requiresOnDevice(onDeviceSupported: Bool, serverAllowed: Bool) -> Bool {
        onDeviceSupported || !serverAllowed
    }

    /// Runs one recognition task for `request`. On a final result, either ends the turn (the
    /// person released the key) or -- when they're still holding it and Apple just ended this
    /// utterance on its own -- folds the text into `finalizedText` and opens a fresh request/task
    /// so the rest of the hold still gets heard (see the stored properties' comment).
    private func beginRecognition(request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer, turn: RecognitionTurn) {
        let newTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            // Every mutation below re-checks ownership inside its own critical section: a cancel
            // or restart can advance `generation` at any point after an earlier check passed.
            if let result {
                let text = result.bestTranscription.formattedString
                let combined = self.lock.withLock { () -> String? in
                    guard self.generation == turn.sessionID else { return nil }
                    let joined = self.finalizedText.isEmpty ? text : self.finalizedText + " " + text
                    self.latest = joined
                    self.recorder = SpeechRecorder.reduce(self.recorder, .resultArrived(session: turn.sessionID)).0
                    return joined
                }
                guard let combined else { return }
                turn.emit(combined, legacy: self.onPartial, identified: self.onIdentifiedPartial)
                if result.isFinal {
                    let nextRequest = self.makeRequest(recognizer: recognizer)
                    let effects = self.lock.withLock { () -> [SpeechRecorder.Effect] in
                        let (next, effects) = SpeechRecorder.reduce(self.recorder, .utteranceEnded(session: turn.sessionID))
                        self.recorder = next
                        if effects.contains(.restart) {
                            self.finalizedText = combined.trimmingCharacters(in: .whitespaces)
                            self.request = nextRequest
                        }
                        return effects
                    }
                    if effects.contains(.finishTurn) {
                        self.finish(ifSession: turn.sessionID)
                    } else if effects.contains(.restart) {
                        self.beginRecognition(request: nextRequest, recognizer: recognizer, turn: turn.restarted())
                    }
                }
            }
            // An error while the key is still held (for example "no speech" during a long
            // silence) must not end recognition for the rest of the hold: reopen a request,
            // keeping the text so far. After a few errors in a row with no result between
            // them, or once the person released, the turn ends instead of retrying forever.
            if error != nil, result?.isFinal != true {
                let nextRequest = self.makeRequest(recognizer: recognizer)
                let effects = self.lock.withLock { () -> [SpeechRecorder.Effect] in
                    let (next, effects) = SpeechRecorder.reduce(
                        self.recorder, .recognitionFailed(session: turn.sessionID, maxRestarts: Self.maxErrorRestarts))
                    self.recorder = next
                    if effects.contains(.restart) {
                        self.finalizedText = self.latest.trimmingCharacters(in: .whitespaces)
                        self.request = nextRequest
                    }
                    return effects
                }
                if effects.contains(.finishTurn) {
                    self.finish(ifSession: turn.sessionID)
                } else if effects.contains(.restart) {
                    self.beginRecognition(request: nextRequest, recognizer: recognizer, turn: turn.restarted())
                }
            }
        }
        // Install the task only while this session still owns the recognizer; a task that lost
        // ownership between creation and here is cancelled instead of replacing the new one.
        let owned = lock.withLock { () -> Bool in
            guard generation == turn.sessionID else { return false }
            task = newTask
            recorder = SpeechRecorder.reduce(recorder, .taskInstalled(session: turn.sessionID)).0
            return true
        }
        if !owned { newTask.cancel() }
    }

    private static let maxErrorRestarts = 3

    /// Debug/E2E only (PLAN-QA7 P0 item J, "quiet hours": the Mac must make no sound 21:00-09:30
    /// BRT, Tony was woken by a prior round's audible mic/speaker checks). Swaps the live
    /// microphone for a WAV file's audio while a turn is already running (`start()` already
    /// called by a real hold-to-dictate key press), so the exact same request/recognizer/
    /// self-correct/auto-insert pipeline a live mic turn uses gets proven without playing
    /// anything through the speakers: the E2E harness renders the phrase silently with `say -o`
    /// and feeds the resulting file in here. Paces delivery to roughly real time, matching the
    /// live tap's own buffer size, so the recognizer's end-of-utterance timing behaves the same
    /// as a real hold; suppresses the live (silent-room) tap for the duration so the two audio
    /// sources never interleave on the same request.
    /// Returns true only when the whole file was fed and this inject still owned the session at
    /// the tail; false means it was cancelled or replaced and must not be treated as completion.
    @discardableResult
    func injectFile(url: URL, expectedSession: Int? = nil) async throws -> Bool {
        let owner = expectedSession ?? lock.withLock { generation }
        let file = try AVAudioFile(forReading: url)
        VoiceLog.log("inject", "file \(url.lastPathComponent) frames \(file.length) fileFormat \(file.processingFormat)")
        guard file.length > 0, let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw InputError.recognizerUnavailable
        }
        try file.read(into: source)
        // E2E WAV is LEI16@16000 mono; convert once and append. Do not read `engine.inputNode`
        // format when the engine is not running (it was 2ch 44100 and garbled recognition).
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            throw InputError.recognizerUnavailable
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw InputError.recognizerUnavailable
        }
        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { throw InputError.recognizerUnavailable }
        let conversionInput = PCMConversionInput(buffer: source, final: true)
        var convertError: NSError?
        converter.convert(to: converted, error: &convertError) { _, status in
            conversionInput.take(status: status)
        }
        VoiceLog.log("inject", "convert error \(String(describing: convertError)) convertedFrames \(converted.frameLength)")
        guard convertError == nil, converted.frameLength > 0 else { throw InputError.recognizerUnavailable }

        lock.withLock { Self.acquireLiveTapSuppression(owner: owner, current: generation, suppress: &suppressLiveTap) }
        // Only the session that set the flag clears it; a newer inject-only session owns its own.
        defer { lock.withLock { Self.releaseLiveTapSuppression(owner: owner, current: generation, suppress: &suppressLiveTap) } }

        let chunkSize: AVAudioFrameCount = 1024
        var offset: AVAudioFrameCount = 0
        let total = converted.frameLength
        let channels = Int(targetFormat.channelCount)
        var chunksSent = 0
        while offset < total {
            // Cancelled or replaced meanwhile: don't feed this file into a newer session's request.
            guard lock.withLock({ generation }) == owner else { return false }
            let length = min(chunkSize, total - offset)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: length) else { break }
            chunk.frameLength = length
            for channel in 0..<channels {
                guard let src = converted.floatChannelData?[channel], let dst = chunk.floatChannelData?[channel] else { continue }
                dst.update(from: src + Int(offset), count: Int(length))
            }
            let currentRequest = lock.withLock { request }
            currentRequest?.append(chunk)
            chunksSent += 1
            offset += length
            let seconds = Double(length) / targetFormat.sampleRate
            try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
        }
        VoiceLog.log("inject", "done, sent \(chunksSent) chunks (\(total) frames)")
        // The last chunk's sleep is an await: re-check the owner in the same critical section
        // that ends the audio, so a replaced session's request is never ended from here.
        return lock.withLock {
            Self.applyInjectTail(owner: owner, current: generation, stopRequested: &stopRequested,
                                 endAudio: { request?.endAudio() })
        }
    }

    /// The inject tail: ends audio and marks the stop only for the session that owns it.
    static func applyInjectTail(owner: Int, current: Int, stopRequested: inout Bool,
                                endAudio: () -> Void) -> Bool {
        guard current == owner else { return false }
        stopRequested = true
        endAudio()
        return true
    }

    /// A new live-mic session starts with the tap un-suppressed, whatever an earlier inject left.
    static func resetLiveTapSuppression(suppress: inout Bool) {
        suppress = false
    }

    /// Sets the live-tap suppression only when `owner` is still the current session.
    static func acquireLiveTapSuppression(owner: Int, current: Int, suppress: inout Bool) {
        if current == owner { suppress = true }
    }

    /// The stop timeout may only finish the session whose `stop()` armed it.
    static func shouldFinishAfterStopTimeout(session: Int, current: Int) -> Bool {
        session == current
    }

    /// Clears the live-tap suppression only when `owner` is still the current session.
    static func releaseLiveTapSuppression(owner: Int, current: Int, suppress: inout Bool) {
        if current == owner { suppress = false }
    }

    /// The audio heard since `start()`, as 16 kHz mono samples (when `recordsSamples`).
    func takeSamples() -> [Float] {
        lock.withLock {
            defer { samples = [] }
            return samples
        }
    }

    /// Stops listening and returns the final transcript (waits at most 1.5 s for it).
    /// Without Apple recognition it returns at once with an empty transcript.
    func stop() async -> String {
        let session = lock.withLock { () -> Int in
            stopRequested = true
            return generation
        }
        stopAudio()
        guard recognizes else { return "" }
        let (alreadyDone, text) = lock.withLock { () -> (Bool, String) in
            request?.endAudio()
            return (finished, latest)
        }
        if alreadyDone { return text }

        return await withCheckedContinuation { continuation in
            let doneText: String? = lock.withLock {
                if finished { return latest }
                waiters.append(continuation)
                return nil
            }
            if let doneText {
                continuation.resume(returning: doneText)
                return
            }
            // QA7 round 10 (real E2E, flaky): a self-correction turn needs an extra recognition
            // pass (the mid-hold-pause fix above opens a fresh request when Apple ends the first
            // utterance early), so its true final result can take a little longer to land than a
            // single-pass turn's -- 1.5 s cut one off before it arrived, returning a stale/garbage
            // partial (e.g. "Yeah.") instead of waiting the extra few hundred ms for the real one.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { return }
                self.finish(ifSession: session)
            }
        }
    }

    func cancel() {
        let oldTask = lock.withLock { () -> SFSpeechRecognitionTask? in
            stopRequested = true
            defer { task = nil }
            return task
        }
        stopAudio()
        oldTask?.cancel()
        finish()
    }

    private func stopAudio() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        let current = lock.withLock { engine }
        if current.isRunning { current.stop() }
        current.inputNode.removeTap(onBus: 0)
    }

    private func reportCaptureFailure(_ failure: CaptureFailure, session: Int, origin: UInt64) {
        onCaptureFailure?(session, origin, failure)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lock.withLock({ self.generation == session }) else { return }
            self.cancel()
        }
    }

    /// Marks the stop-timeout finish only if `session` is still current. The ownership check and
    /// the finished/waiter transition are one step, so a replacement session cannot slip between.
    static func finishWaitersIfOwned<W>(session: Int, current: Int, finished: inout Bool,
                                        waiters: inout [W]) -> [W]? {
        guard shouldFinishAfterStopTimeout(session: session, current: current) else { return nil }
        finished = true
        let pending = waiters
        waiters = []
        return pending
    }

    private func finish(ifSession session: Int) {
        lock.lock()
        let pending = Self.finishWaitersIfOwned(session: session, current: generation,
                                                finished: &finished, waiters: &waiters)
        let text = latest
        lock.unlock()
        pending?.forEach { $0.resume(returning: text) }
    }

    private func finish() {
        lock.lock()
        finished = true
        let pending = waiters
        waiters = []
        let text = latest
        lock.unlock()
        pending.forEach { $0.resume(returning: text) }
    }
}
