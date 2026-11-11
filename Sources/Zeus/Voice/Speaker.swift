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
            if let self, self.pumpToken == token { self.pump = nil; self.pumpToken = nil }
        }
    }

    func speak(sentenceStream: AsyncStream<String>) async -> SpeakOutcome {
        ExplanationAudioArbitration.yieldToNewCapture()
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

    /// Warms the engine the next reply will use. Called on the first talk-key press, never at launch.
    func prewarm() {
        let settings = VoiceSettings.shared
        guard let decision = settings.routeDecisions().first, prewarmed != decision.engine else { return }
        prewarmed = decision.engine
        chain.prepare()
        switch decision.engine {
        case .kokoro:
            let (name, speed) = (settings.kokoroVoice, settings.kokoroSpeed)
            Task { await KokoroWorkerSession.shared.prewarm(voice: name, speed: speed) }
        case .elevenLabs:
            VoiceDesigner.designUltronVoiceOnce()
        default:
            break
        }
        VoiceLog.log("prewarm", "engine=\(decision.engine.logName) reason=\(decision.reason)")
    }

    func stop() {
        queue.removeAll()
        pump?.cancel()
        pump = nil
        pumpToken = nil
        chain.stop()
        synthesizer.stopSpeaking(at: .immediate)
        systemRendering = false
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
        switch engine {
        case .elevenLabs:
            if let id = await speakElevenLabs(text, began: began) {
                settings.clearProviderPause(.elevenLabs)
                return id
            }
            if Self.countsAsFailure(), !settings.isProviderPaused(.elevenLabs) { settings.noteProviderFailure(.elevenLabs, reason: .other("no audio")) }
            return nil
        case .openAI:
            if let voice = await speakOpenAI(text, began: began) {
                settings.clearProviderPause(.openAICompatible)
                return voice
            }
            if Self.countsAsFailure() { settings.noteProviderFailure(.openAICompatible, reason: .offline) }
            return nil
        case .kokoro:
            if await speakKokoro(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed, began: began) {
                settings.clearProviderPause(.kokoro)
                return settings.kokoroVoice
            }
            if Self.countsAsFailure() { settings.noteProviderFailure(.kokoro, reason: .missingModel) }
            return nil
        case .chatterbox:
            if await speakChatterbox(text, began: began) {
                settings.clearProviderPause(.chatterbox)
                return "reference"
            }
            if Self.countsAsFailure() { settings.noteProviderFailure(.chatterbox, reason: .missingModel) }
            return nil
        case .system:
            return await speakSystem(text)
        }
    }

    /// A line that produced nothing counts against its engine only when nobody interrupted it.
    private static func countsAsFailure() -> Bool {
        SpeechAttemptPolicy.shouldRecordFailure(producedAudio: false, cancelled: Task.isCancelled)
    }

    private func markAudioReady() {
        if audioReadyAt == nil { audioReadyAt = Date() }
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
    }

    // MARK: Engines

    private func speakElevenLabs(_ text: String, began: Date) async -> String? {
        for route in ElevenLabsVoice.loadRoutes() {
            var gotAudio = false
            let deadline = began.addingTimeInterval(VoiceTTSChain.firstAudioTimeout)
            do {
                let (bytes, response) = try await Self.urlSession.bytes(for: route.request(for: text))
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    var body = Data()
                    for try await byte in bytes { body.append(byte); if body.count > 8_192 { break } }
                    if ElevenLabsVoice.isKeyRejection(http.statusCode) {
                        VoiceSettings.shared.noteElevenLabsKeyRejected(status: http.statusCode, body: body)
                    }
                    continue
                }
                var chunk = Data()
                chunk.reserveCapacity(4_800)
                for try await byte in bytes {
                    if Task.isCancelled { return gotAudio ? route.voiceID ?? "default" : nil }
                    if !gotAudio, Date() > deadline { break }
                    chunk.append(byte)
                    if chunk.count >= 4_800 {
                        if chain.scheduleInt16(chunk) { if !gotAudio { markAudioReady() }; gotAudio = true }
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty, chain.scheduleInt16(chunk) { if !gotAudio { markAudioReady() }; gotAudio = true }
            } catch {
                if gotAudio { return route.voiceID ?? "default" }
                continue
            }
            if gotAudio { return Self.routeVoice(route) }
        }
        return nil
    }

    private static func routeVoice(_ route: ElevenLabsVoice) -> String {
        let id = ElevenLabsVoice.savedVoiceID() ?? route.voiceID ?? ElevenLabsVoice.defaultVoiceID
        return "\(route.engineName):\(id)"
    }

    private func speakOpenAI(_ text: String, began: Date) async -> String? {
        guard let prepared = OpenAITTSVoice.streamingRequest(text) else { return nil }
        let deadline = began.addingTimeInterval(VoiceTTSChain.firstAudioTimeout)
        do {
            let (bytes, response) = try await Self.urlSession.bytes(for: prepared.request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            if prepared.rawPCM {
                var gotAudio = false
                var chunk = Data()
                for try await byte in bytes {
                    if Task.isCancelled { break }
                    if !gotAudio, Date() > deadline { break }
                    chunk.append(byte)
                    if chunk.count >= 4_800 {
                        if chain.scheduleInt16(chunk) { if !gotAudio { markAudioReady() }; gotAudio = true }
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty, SpeechAttemptPolicy.mayPlay(cancelled: Task.isCancelled), chain.scheduleInt16(chunk) { if !gotAudio { markAudioReady() }; gotAudio = true }
                return gotAudio ? prepared.voice : nil
            }
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-openai-tts-\(UUID().uuidString).wav")
            try body.write(to: url)
            guard SpeechAttemptPolicy.mayPlay(cancelled: Task.isCancelled) else { try? FileManager.default.removeItem(at: url); return nil }
            guard chain.scheduleFile(url) else { return nil }
            markAudioReady()
            return prepared.voice
        } catch {
            return nil
        }
    }

    private func speakKokoro(_ text: String, voice: String, speed: Double, began: Date) async -> Bool {
        guard let url = await KokoroVoice.render(text, voice: voice, speed: speed) else { return false }
        // Rendering takes seconds: if the owner interrupted meanwhile, the finished line is thrown away, never played.
        guard SpeechAttemptPolicy.mayPlay(cancelled: Task.isCancelled) else { try? FileManager.default.removeItem(at: url); return false }
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
        guard SpeechAttemptPolicy.mayPlay(cancelled: Task.isCancelled) else { try? FileManager.default.removeItem(at: url); return false }
        guard chain.scheduleFile(url) else { return false }
        markAudioReady()
        return true
    }

    /// The deepest Mac voice, rendered to buffers and played through the Ultron chain. If the system
    /// produces no buffers it is spoken directly, still with the deep voice, never the default one.
    private func speakSystem(_ text: String) async -> String? {
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

    /// The deepest male macOS voice for the language, never Samantha. Nil when none qualifies.
    nonisolated static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().map {
            UltronSystemVoicePick.Candidate(name: $0.name, language: $0.language, quality: $0.quality.rawValue, identifier: $0.identifier)
        }
        guard let pick = UltronSystemVoicePick.pick(from: candidates, languageCode: languageCode) else { return nil }
        return AVSpeechSynthesisVoice(identifier: pick.identifier)
    }
}
