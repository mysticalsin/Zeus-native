import AVFoundation
import Foundation
import ZeusCore

/// Speaks reply sentences. `UltronEngineRouter` picks the engine (ElevenLabs, OpenAI, Kokoro, then the
/// deepest Mac voice) with a logged reason, and every engine's audio, the Mac voice included, runs
/// through the Ultron effect chain (`UltronAudioChain`). Each sentence is scheduled for playback as soon
/// as its first audio arrives, so the next sentence is requested while the previous one plays.
@MainActor
final class Speaker: SentenceSpeaking {
    nonisolated(unsafe) static var urlSession: URLSession = .shared
    /// One warm HTTP/2 session per TTS provider: the connection the key-down warm-up opens is the one the
    /// first sentence reuses.
    nonisolated(unsafe) static var elevenLabsSession: URLSession = TTSHTTP.makeSession()
    nonisolated(unsafe) static var openAISession: URLSession = TTSHTTP.makeSession()

    struct Played: Equatable {
        var engine: UltronEngine
        var voice: String
        var reason: String
        var firstAudioMs: Int?
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let chain = UltronAudioChain()
    private var queue: [String] = []
    private var pump: Task<Void, Never>?
    private var pumpToken: UUID?
    private var systemRendering = false
    private var prewarmed: UltronEngine?
    /// When the audio for the line now playing was first ready. Speech-start is measured to this.
    private var audioReadyAt: Date?
    /// The ElevenLabs model for the answer in flight. One model speaks the whole answer.
    private var answerPin = AnswerModelPin()
    private var answerHadAudio = false
    /// Studio was rejected by ElevenLabs on this launch: later answers use the fast model without trying it.
    private var studioUnsupported = false
    private(set) var lastElevenModel: String?
    private var lastElevenStatus: Int?
    private var systemVoices: [String: AVSpeechSynthesisVoice?] = [:]

    /// Apple's own default speaking rate: the premium voices are tuned for it.
    nonisolated static let systemRate = AVSpeechUtteranceDefaultSpeechRate

    /// Posted when the talk key goes down. The first one warms the engine the next reply will use.
    nonisolated static let talkKeyPressed = Notification.Name("app.zeus.voice.talkKeyPressed")

    init(languageCode: String) {
        voice = Self.bestVoice(for: languageCode)
        NotificationCenter.default.addObserver(forName: Self.talkKeyPressed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prewarm() }
        }
        let fallback = voice.map { "\($0.name) \(Self.qualityName($0.quality))" } ?? "none found"
        NSLog("[ZEUS] voice: ready engines=%@ fallback=system %@", VoiceSettings.shared.routeDecisions().map(\.engine.logName).joined(separator: ","), fallback)
    }

    nonisolated static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "premium"
        case .enhanced: "enhanced"
        default: "default"
        }
    }

    var systemVoiceName: String { voice?.name ?? "default" }

    var isSpeaking: Bool { synthesizer.isSpeaking || pump != nil || chain.isPlaying || systemRendering }

    var engineDescription: String {
        guard let first = VoiceSettings.shared.routeDecisions().first else { return "Mac voice \(systemVoiceName) with the Ultron effect" }
        return first.engine == .system ? "Mac voice \(systemVoiceName) with the Ultron effect" : "\(first.engine.label) with the Ultron effect"
    }

    // MARK: Entry points

    func speak(_ text: String) {
        ExplanationAudioArbitration.yieldToNewCapture()
        queue.append(text)
        guard pump == nil else { return }
        let token = UUID()
        pumpToken = token
        pump = Task { [weak self] in
            while let self, !Task.isCancelled {
                if !self.queue.isEmpty {
                    _ = await self.speakLine(self.queue.removeFirst())
                } else if self.chain.isPlaying || self.systemRendering {
                    try? await Task.sleep(for: .milliseconds(40))
                } else {
                    break
                }
            }
            if let self, self.pumpToken == token { self.pump = nil; self.pumpToken = nil; self.endAnswer() }
        }
    }

    private func endAnswer() {
        answerPin.reset()
        answerHadAudio = false
    }

    func speak(sentenceStream: AsyncStream<String>) async -> SpeakOutcome {
        ExplanationAudioArbitration.yieldToNewCapture()
        defer { endAnswer() }
        let began = Date()
        var first: Played?
        var count = 0
        for await sentence in sentenceStream {
            if Task.isCancelled { break }
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let played = await speakLine(text, began: count == 0 ? began : Date())
            if first == nil { first = played }
            count += 1
        }
        while (chain.isPlaying || systemRendering), !Task.isCancelled { try? await Task.sleep(for: .milliseconds(40)) }
        return SpeakOutcome(engine: first?.engine.logName ?? "none", voice: first?.voice ?? "", reason: first?.reason ?? "nothing was spoken",
                            firstAudioMs: first?.firstAudioMs, sentences: count)
    }

    /// Warms the engine the next reply will use. Called on every talk-key press, never at launch. Cloud voices
    /// re-open their connection (throttled in `TTSHTTP`); local engines warm once.
    func prewarm() {
        let settings = VoiceSettings.shared
        guard let decision = settings.routeDecisions().first else { return }
        switch decision.engine {
        case .elevenLabs:
            Task.detached { await TTSHTTP.warmElevenLabs() }
        case .openAI:
            Task.detached { await TTSHTTP.warmOpenAI() }
        case .kokoro:
            guard prewarmed != decision.engine else { return }
            let (name, speed) = (settings.kokoroVoice, settings.kokoroSpeed)
            Task { await KokoroWorkerSession.shared.prewarm(voice: name, speed: speed) }
        default:
            break
        }
        chain.prepare()
        if prewarmed != decision.engine {
            prewarmed = decision.engine
            VoiceLog.log("prewarm", "engine=\(decision.engine.logName) reason=\(decision.reason)")
        }
    }

    func stop() {
        queue.removeAll()
        pump?.cancel()
        pump = nil
        pumpToken = nil
        chain.stop()
        synthesizer.stopSpeaking(at: .immediate)
        systemRendering = false
        endAnswer()
    }

    // MARK: Choosing and playing

    /// Tries each engine in router order until one produces audio. Returns nil only when nothing could speak.
    private func speakLine(_ text: String, began: Date = Date()) async -> Played? {
        let settings = VoiceSettings.shared
        for decision in settings.routeDecisions() {
            if Task.isCancelled { return nil }
            audioReadyAt = nil
            guard let voiceName = await attempt(decision.engine, text, settings: settings, began: began) else { continue }
            let ms = audioReadyAt.map { Int($0.timeIntervalSince(began) * 1000) }
            if let ms { settings.recordFirstAudio(decision.engine, ms: ms) }
            logSpoken(engine: decision.engine, voice: voiceName, reason: decision.reason, firstAudioMs: ms)
            return Played(engine: decision.engine, voice: voiceName, reason: decision.reason, firstAudioMs: ms)
        }
        return nil
    }

    /// One engine, one sentence. The voice name on success, nil when this engine could not speak it.
    private func attempt(_ engine: UltronEngine, _ text: String, settings: VoiceSettings, began: Date) async -> String? {
        VoiceLatency.shared.mark(.ttsRequest)
        switch engine {
        case .elevenLabs:
            if let id = await speakElevenLabs(text, began: began) {
                settings.clearProviderPause(.elevenLabs)
                return id
            }
            if !settings.isProviderPaused(.elevenLabs) { settings.noteProviderFailure(.elevenLabs, reason: .other("no audio")) }
            return nil
        case .openAI:
            if let voice = await speakOpenAI(text, began: began) {
                settings.clearProviderPause(.openAICompatible)
                return voice
            }
            settings.noteProviderFailure(.openAICompatible, reason: .offline)
            return nil
        case .kokoro:
            if await speakKokoro(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed, began: began) {
                settings.clearProviderPause(.kokoro)
                return settings.kokoroVoice
            }
            settings.noteProviderFailure(.kokoro, reason: .missingModel)
            return nil
        case .chatterbox:
            if await speakChatterbox(text, began: began) {
                settings.clearProviderPause(.chatterbox)
                return "reference"
            }
            settings.noteProviderFailure(.chatterbox, reason: .missingModel)
            return nil
        case .system:
            return await speakSystem(text)
        }
    }

    private func markAudioReady() {
        if audioReadyAt == nil { audioReadyAt = Date() }
        VoiceLatency.shared.mark(.firstAudio)
    }

    /// One `engine=... voice=... reason=...` line in voice.log for the reply that is actually spoken.
    private func logSpoken(engine: UltronEngine, voice: String, reason: String, firstAudioMs: Int?) {
        let ready = audioReadyAt
        audioReadyAt = nil
        var line = UltronVoicePlan.logLine(engine: engine.logName, voice: voice) + " effect=\(Int(UltronEffectParameters.percent(fromIntensity: UltronVoiceEffect.intensity)))%"
            + " reason=\(reason)"
        if let ms = firstAudioMs { line += " first_audio_ms=\(ms)" }
        if let ms = VoiceAnswerLatency.consumeSpeechStartMs(speechBegan: ready) { line += " speech_start_ms=\(ms)" }
        VoiceLog.log("speak", line)
        let model: String? = switch engine {
        case .elevenLabs: lastElevenModel
        case .openAI: OpenAITTSVoice.config()?.model
        default: nil
        }
        VoiceLatency.shared.setSpeech(engine: engine.logName, voice: voice, model: model, reason: reason,
                                      effectPercent: Int(UltronEffectParameters.percent(fromIntensity: UltronVoiceEffect.intensity)))
    }

    // MARK: Engines

    /// One model speaks the whole answer. The model is fixed at the answer's first sentence; if Studio is
    /// refused before any audio of the answer has played, the whole answer uses the fast model instead.
    private func speakElevenLabs(_ text: String, began: Date) async -> String? {
        let model = answerPin.resolve(quality: VoiceSettings.shared.elevenQuality, studioUnsupported: studioUnsupported)
        lastElevenStatus = nil
        var result = await speakElevenLabs(text, began: began, model: model)
        if result == nil, model == ElevenLabsQuality.studioModel, !answerHadAudio, !Task.isCancelled {
            if let status = lastElevenStatus, AnswerModelPin.isModelRejection(status: status) { studioUnsupported = true }
            answerPin.fallBackToFast()
            VoiceLog.log("voice", "studio model not available; this answer uses \(ElevenLabsQuality.fastModel)")
            result = await speakElevenLabs(text, began: began, model: ElevenLabsQuality.fastModel)
        }
        if result != nil {
            answerHadAudio = true
            lastElevenModel = answerPin.model ?? model
        }
        return result
    }

    private func speakElevenLabs(_ text: String, began: Date, model: String) async -> String? {
        for route in ElevenLabsVoice.loadRoutes() {
            let feeder = PCMStreamFeeder(chain: chain) { [weak self] in self?.markAudioReady() }
            let deadline = began.addingTimeInterval(VoiceTTSChain.firstAudioTimeout)
            do {
                let (bytes, response) = try await Self.elevenLabsSession.bytes(for: route.request(for: text, model: model))
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastElevenStatus = http.statusCode
                    var body = Data()
                    for try await byte in bytes { body.append(byte); if body.count > 8_192 { break } }
                    if ElevenLabsVoice.isKeyRejection(http.statusCode) {
                        VoiceSettings.shared.noteElevenLabsKeyRejected(status: http.statusCode, body: body)
                    }
                    continue
                }
                var chunk = Data()
                chunk.reserveCapacity(Self.pcmChunkBytes)
                for try await byte in bytes {
                    if Task.isCancelled { feeder.discard(); return feeder.scheduledAny ? Self.routeVoice(route) : nil }
                    if !feeder.receivedAny, Date() > deadline { break }
                    chunk.append(byte)
                    if chunk.count >= Self.pcmChunkBytes {
                        feeder.push(chunk)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                feeder.push(chunk)
                feeder.finish()
            } catch {
                if Task.isCancelled { feeder.discard() } else { feeder.finish() }
                if feeder.scheduledAny { return Self.routeVoice(route) }
                continue
            }
            if feeder.scheduledAny { return Self.routeVoice(route) }
        }
        return nil
    }

    /// 50 ms of 24 kHz 16-bit mono PCM: small enough to start fast, with a one-buffer look-ahead for the tail fade.
    private static let pcmChunkBytes = 2_400

    private static func routeVoice(_ route: ElevenLabsVoice) -> String {
        let id = ElevenLabsVoice.savedVoiceID() ?? route.voiceID ?? ElevenLabsVoice.defaultVoiceID
        return "\(route.engineName):\(id)"
    }

    private func speakOpenAI(_ text: String, began: Date) async -> String? {
        guard let prepared = OpenAITTSVoice.streamingRequest(text) else { return nil }
        let deadline = began.addingTimeInterval(VoiceTTSChain.firstAudioTimeout)
        let feeder = PCMStreamFeeder(chain: chain) { [weak self] in self?.markAudioReady() }
        do {
            let (bytes, response) = try await Self.openAISession.bytes(for: prepared.request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            if prepared.rawPCM {
                var chunk = Data()
                for try await byte in bytes {
                    if Task.isCancelled { feeder.discard(); break }
                    if !feeder.receivedAny, Date() > deadline { break }
                    chunk.append(byte)
                    if chunk.count >= Self.pcmChunkBytes {
                        feeder.push(chunk)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                feeder.push(chunk)
                feeder.finish()
                return feeder.scheduledAny ? prepared.voice : nil
            }
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-openai-tts-\(UUID().uuidString).wav")
            try body.write(to: url)
            guard chain.scheduleFile(url) else { return nil }
            markAudioReady()
            return prepared.voice
        } catch {
            feeder.discard()
            return nil
        }
    }

    private func speakKokoro(_ text: String, voice: String, speed: Double, began: Date) async -> Bool {
        guard let url = await KokoroVoice.render(text, voice: voice, speed: speed) else { return false }
        if Date().timeIntervalSince(began) > VoiceTTSChain.firstAudioTimeout + 30 {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        guard chain.scheduleFile(url) else { return false }
        markAudioReady()
        return true
    }

    private func speakChatterbox(_ text: String, began: Date) async -> Bool {
        guard let url = await ChatterboxVoice.render(text) else { return false }
        guard chain.scheduleFile(url) else { return false }
        markAudioReady()
        return true
    }

    /// The deepest Mac voice, rendered to buffers and played through the Ultron chain. If the system
    /// produces no buffers it is spoken directly, still with the deep voice, never the default one.
    private func speakSystem(_ text: String) async -> String? {
        // The answer is spoken in the language Tony used: the best installed voice for that language.
        let voice = SpokenLanguage.detect(text).flatMap { systemVoice(forLanguage: $0) } ?? self.voice
        let name = voice.map { "\($0.name) \(Self.qualityName($0.quality))" } ?? "default"
        func utterance() -> AVSpeechUtterance {
            let item = AVSpeechUtterance(string: text)
            item.voice = voice
            item.rate = UltronSystemVoicePick.rate(defaultRate: Self.systemRate)
            item.pitchMultiplier = UltronSystemVoicePick.pitchMultiplier
            item.prefersAssistiveTechnologySettings = false
            return item
        }
        guard chain.prepare() else {
            markAudioReady()
            synthesizer.speak(utterance())
            return name + " (no audio output for the effect)"
        }
        let (stream, continuation) = AsyncStream<SystemVoiceRender.Box>.makeStream()
        systemRendering = true
        SystemVoiceRender.render(utterance(), with: synthesizer,
                                 deliver: { continuation.yield($0) }, finished: { continuation.finish() })
        var gotAudio = false
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !gotAudio { continuation.finish() }
        }
        for await box in stream {
            if Task.isCancelled { break }
            if chain.schedule(box.buffer) {
                if !gotAudio { markAudioReady() }
                gotAudio = true
            }
        }
        watchdog.cancel()
        systemRendering = false
        if !gotAudio, !Task.isCancelled {
            VoiceLog.log("speak", "system voice gave no buffers; speaking it directly")
            markAudioReady()
            synthesizer.speak(utterance())
        }
        return name
    }

    private func systemVoice(forLanguage code: String) -> AVSpeechSynthesisVoice? {
        if let current = voice, current.language.lowercased().hasPrefix(code) { return current }
        if let cached = systemVoices[code] { return cached }
        let picked = Self.bestVoice(for: code)
        systemVoices[code] = picked
        return picked
    }

    // MARK: Silent preview and self-test

    /// Renders one line to a WAV for silent Settings tests (K2), through the Ultron chain offline.
    func renderTestLine(_ text: String, to destination: URL) async -> Bool {
        let settings = VoiceSettings.shared
        for decision in settings.routeDecisions() {
            switch decision.engine {
            case .system:
                if await renderSystem(text, to: destination) { return true }
            case .elevenLabs:
                if let url = await renderElevenLabsFile(text), (try? VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)) != nil {
                    try? FileManager.default.removeItem(at: url)
                    return true
                }
            case .openAI:
                if let url = await OpenAITTSVoice.render(text, session: Self.urlSession), (try? VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)) != nil {
                    try? FileManager.default.removeItem(at: url)
                    return true
                }
            case .kokoro:
                if let url = await KokoroVoice.render(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed),
                   (try? VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)) != nil {
                    try? FileManager.default.removeItem(at: url)
                    return true
                }
            case .chatterbox:
                if let url = await ChatterboxVoice.render(text), (try? VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)) != nil {
                    try? FileManager.default.removeItem(at: url)
                    return true
                }
            }
        }
        return false
    }

    private func renderSystem(_ text: String, to destination: URL) async -> Bool {
        let item = AVSpeechUtterance(string: text)
        item.voice = voice
        item.rate = UltronSystemVoicePick.rate(defaultRate: Self.systemRate)
        item.pitchMultiplier = UltronSystemVoicePick.pitchMultiplier
        let (stream, continuation) = AsyncStream<SystemVoiceRender.Box>.makeStream()
        SystemVoiceRender.render(item, with: synthesizer, deliver: { continuation.yield($0) }, finished: { continuation.finish() })
        var buffers: [AVAudioPCMBuffer] = []
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            continuation.finish()
        }
        for await box in stream { if let converted = UltronAudioChain.convert(box.buffer) { buffers.append(converted) } }
        watchdog.cancel()
        let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard frames > 0, let joined = AVAudioPCMBuffer(pcmFormat: UltronAudioChain.format, frameCapacity: AVAudioFrameCount(frames)),
              let target = joined.floatChannelData?[0] else { return false }
        var offset = 0
        for buffer in buffers {
            guard let source = buffer.floatChannelData?[0] else { continue }
            for index in 0..<Int(buffer.frameLength) { target[offset + index] = source[index] }
            offset += Int(buffer.frameLength)
        }
        joined.frameLength = AVAudioFrameCount(frames)
        guard let processed = UltronOfflineRender.render(joined, parameters: UltronVoiceEffect.parameters),
              let file = try? AVAudioFile(forWriting: destination, settings: UltronAudioChain.format.settings),
              (try? file.write(from: processed)) != nil else { return false }
        return true
    }

    private func renderElevenLabsFile(_ text: String) async -> URL? {
        guard let route = ElevenLabsVoice.loadRoutes().first else { return nil }
        do {
            let (data, response) = try await Self.urlSession.data(for: route.request(for: text))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-eleven-\(UUID().uuidString).pcm")
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// The owner's self-test: one fixed line through every engine that is available, with the effect.
    func selfTest(line: String, muted: Bool) async -> [VoiceSelfTestRow] {
        let settings = VoiceSettings.shared
        let availability = settings.ultronAvailability()
        let percent = Int(UltronEffectParameters.percent(fromIntensity: UltronVoiceEffect.intensity))
        chain.muted = muted
        defer { chain.muted = false }
        var rows: [VoiceSelfTestRow] = []
        for engine in UltronEngine.allCases {
            if let why = availability.skipReason(engine) {
                rows.append(VoiceSelfTestRow(engine: engine.logName, available: false, reason: why, spoke: false, firstAudioMs: nil, effectPercent: percent))
                continue
            }
            stop()
            audioReadyAt = nil
            let began = Date()
            let name = await attempt(engine, line, settings: settings, began: began)
            let ms = audioReadyAt.map { Int($0.timeIntervalSince(began) * 1000) }
            let waitUntil = Date().addingTimeInterval(25)
            while (chain.isPlaying || systemRendering || synthesizer.isSpeaking), Date() < waitUntil { try? await Task.sleep(for: .milliseconds(80)) }
            let reason = name.map { "spoke with \($0)" } ?? "engine produced no audio"
            rows.append(VoiceSelfTestRow(engine: engine.logName, available: true, reason: reason, spoke: name != nil && ms != nil, firstAudioMs: ms, effectPercent: percent))
        }
        return rows
    }

    // MARK: System voice choice

    nonisolated static func systemCandidates() -> [UltronSystemVoicePick.Candidate] {
        AVSpeechSynthesisVoice.speechVoices().map {
            UltronSystemVoicePick.Candidate(name: $0.name, language: $0.language, quality: $0.quality.rawValue, identifier: $0.identifier)
        }
    }

    /// True when no Enhanced or Premium Mac voice is installed for the language (Settings shows a one-time hint).
    nonisolated static func needsBetterMacVoice(languageCode: String) -> Bool {
        UltronSystemVoicePick.suggestsBetterVoice(from: systemCandidates(), languageCode: languageCode)
    }

    /// The model name for the engine that just spoke, for the Test voice panel.
    func modelDescription(engine: String) -> String {
        switch engine {
        case "elevenlabs": lastElevenModel ?? ElevenLabsQuality.fastModel
        case "openai": OpenAITTSVoice.config()?.model ?? "-"
        default: "-"
        }
    }

    /// The deepest male macOS voice for the language, never Samantha. Nil when none qualifies.
    nonisolated static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = systemCandidates()
        guard let pick = UltronSystemVoicePick.pick(from: candidates, languageCode: languageCode) else { return nil }
        return AVSpeechSynthesisVoice(identifier: pick.identifier)
    }
}

/// Schedules streamed PCM for one sentence with a one-buffer look-ahead, so the last buffer of the sentence
/// can take its tail fade and the first its head fade (`AudioEdge`): sentences join without a click.
@MainActor
final class PCMStreamFeeder {
    private let chain: UltronAudioChain
    private let onFirstAudio: () -> Void
    private var pending: Data?
    private var first = true
    private(set) var receivedAny = false
    private(set) var scheduledAny = false

    init(chain: UltronAudioChain, onFirstAudio: @escaping () -> Void) {
        self.chain = chain
        self.onFirstAudio = onFirstAudio
    }

    func push(_ data: Data) {
        guard !data.isEmpty else { return }
        receivedAny = true
        if let held = pending { flush(held, tail: false) }
        pending = data
    }

    /// The sentence's last buffer, with its tail fade.
    func finish() {
        guard let held = pending else { return }
        pending = nil
        flush(held, tail: true)
    }

    func discard() { pending = nil }

    private func flush(_ data: Data, tail: Bool) {
        if chain.scheduleInt16(data, fadeHead: first, fadeTail: tail) {
            if !scheduledAny { onFirstAudio() }
            scheduledAny = true
        }
        first = false
    }
}
