import AVFoundation
import Foundation
import ZeusCore

/// Speaks reply sentences through the Settings > Voice provider chain (K1/K4), with Ultron post
/// processing on file-based engines and `say` only as the final offline fallback.
@MainActor
final class Speaker {
    nonisolated(unsafe) static var urlSession: URLSession = .shared

    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private let routes: [ElevenLabsVoice]
    private var eleven: ElevenLabsVoice? { routes.first }
    private let player = StreamingPCMPlayer()
    private var queue: [String] = []
    private var pump: Task<Void, Never>?
    private var pumpToken: UUID?

    /// Apple's own default speaking rate: the premium voices are tuned for it.
    nonisolated static let systemRate = AVSpeechUtteranceDefaultSpeechRate

    init(languageCode: String) {
        voice = Self.bestVoice(for: languageCode)
        routes = ElevenLabsVoice.loadRoutes()
        let fallback = voice.map { "\($0.name) \(Self.qualityName($0.quality))" } ?? "default"
        NSLog("[ZEUS] voice: ready engines=%@ fallback=system %@", routes.map(\.engineName).joined(separator: ","), fallback)
    }

    nonisolated static func routeName(_ eleven: ElevenLabsVoice) -> String {
        if case .direct = eleven.route { return "elevenlabs-direct" }
        return "elevenlabs-worker"
    }

    nonisolated static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "premium"
        case .enhanced: "enhanced"
        default: "default"
        }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking || pump != nil || player.isPlaying || filePump != nil }

    var engineDescription: String {
        let settings = VoiceSettings.shared
        let paused = settings.isProviderPaused(.elevenLabs)
        let chain = VoiceTTSChain.providers(
            chosen: settings.ttsProvider,
            availability: settings.ttsAvailability(elevenLabsPaused: paused),
            isPaused: { settings.isProviderPaused($0) }
        )
        if let first = chain.first {
            return Self.describe(provider: first, settings: settings)
        }
        if KokoroVoice.isSetUp {
            return "Kokoro \(settings.kokoroVoice) voice (on this Mac)"
        }
        return voice.map { "system voice (\($0.name) \(Self.qualityName($0.quality)))" } ?? "system voice (default)"
    }

    private static func describe(provider: VoiceTTSProvider, settings: VoiceSettings) -> String {
        switch provider {
        case .kokoro: return "Kokoro \(settings.kokoroVoice) voice (on this Mac)"
        case .chatterbox: return "Local Chatterbox Turbo (Ultron reference)"
        case .elevenLabs: return elevenLabsDescription(settings)
        case .openAICompatible: return "OpenAI-compatible TTS"
        }
    }

    private static func elevenLabsDescription(_ settings: VoiceSettings) -> String {
        if settings.isProviderPaused(.elevenLabs), KokoroVoice.isSetUp {
            return "Kokoro \(ElevenLabsVoice.offlineKokoroVoice) \(ElevenLabsVoice.offlineKokoroSpeed) (ElevenLabs key rejected)"
        }
        return "ElevenLabs George"
    }

    func speak(_ text: String) {
        queue.append(text)
        guard pump == nil else { return }
        let token = UUID()
        pumpToken = token
        pump = Task { [weak self] in
            while let self, !Task.isCancelled, !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                let ok = await self.speakThroughProviders(next)
                if !ok, !Task.isCancelled { self.speakWithSystem(next) }
            }
            if let self, self.pumpToken == token { self.pump = nil; self.pumpToken = nil }
        }
    }

    /// Renders one line to a WAV for silent Settings tests (K2).
    func renderTestLine(_ text: String, to destination: URL) async -> Bool {
        let settings = VoiceSettings.shared
        let chain = VoiceTTSChain.providers(
            chosen: settings.ttsProvider,
            availability: settings.ttsAvailability(elevenLabsPaused: settings.isProviderPaused(.elevenLabs)),
            isPaused: { settings.isProviderPaused($0) }
        )
        for provider in chain {
            if let url = await renderFile(text, provider: provider, settings: settings) {
                do {
                    try VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)
                    try? FileManager.default.removeItem(at: url)
                    VoiceLog.log("test", "Saved, not played (quiet hours) \(destination.lastPathComponent)")
                    return true
                } catch {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        if let url = await KokoroVoice.render(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed) {
            defer { try? FileManager.default.removeItem(at: url) }
            try? VoiceWAVPlayback.writeProcessedCopy(from: url, to: destination)
            return FileManager.default.fileExists(atPath: destination.path)
        }
        return false
    }

    private func speakThroughProviders(_ text: String) async -> Bool {
        let settings = VoiceSettings.shared
        let chain = VoiceTTSChain.providers(
            chosen: settings.ttsProvider,
            availability: settings.ttsAvailability(elevenLabsPaused: settings.isProviderPaused(.elevenLabs)),
            isPaused: { settings.isProviderPaused($0) }
        )
        for provider in chain {
            let began = Date()
            switch provider {
            case .elevenLabs:
                if await speakElevenLabs(text, began: began) {
                    settings.clearProviderPause(.elevenLabs)
                    logSpoken(engine: "elevenlabs", voice: eleven?.voiceID ?? ElevenLabsVoice.defaultVoiceID)
                    return true
                }
                settings.noteProviderFailure(.elevenLabs, reason: .http401)
            case .openAICompatible:
                if await speakOpenAI(text, began: began) {
                    settings.clearProviderPause(.openAICompatible)
                    logSpoken(engine: "openai", voice: "compatible")
                    return true
                }
                settings.noteProviderFailure(.openAICompatible, reason: .offline)
            case .kokoro:
                if await speakKokoroFile(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed, began: began) {
                    settings.clearProviderPause(.kokoro)
                    logSpoken(engine: "kokoro", voice: settings.kokoroVoice)
                    return true
                }
                settings.noteProviderFailure(.kokoro, reason: .missingModel)
            case .chatterbox:
                if await speakChatterbox(text, began: began) {
                    settings.clearProviderPause(.chatterbox)
                    logSpoken(engine: "chatterbox", voice: "reference")
                    return true
                }
                settings.noteProviderFailure(.chatterbox, reason: .missingModel)
            }
        }
        if KokoroVoice.isSetUp {
            let voice = ElevenLabsVoice.offlineKokoroVoice
            let ok = await speakKokoroFile(text, voice: voice, speed: ElevenLabsVoice.offlineKokoroSpeed, began: Date())
            if ok { logSpoken(engine: "kokoro", voice: voice) }
            return ok
        }
        return false
    }

    /// One `engine=... voice=...` line in voice.log for the reply that is actually spoken.
    private func markAudioReady() {
        if audioReadyAt == nil { audioReadyAt = Date() }
    }

    private func logSpoken(engine: String, voice: String) {
        let ready = audioReadyAt
        audioReadyAt = nil
        let base = UltronVoicePlan.logLine(engine: engine, voice: voice)
        if let ms = VoiceAnswerLatency.consumeSpeechStartMs(speechBegan: ready) {
            VoiceLog.log("speak", "\(base) speech_start_ms=\(ms)")
        } else {
            VoiceLog.log("speak", base)
        }
    }

    private func renderFile(_ text: String, provider: VoiceTTSProvider, settings: VoiceSettings) async -> URL? {
        switch provider {
        case .kokoro:
            return await KokoroVoice.render(text, voice: settings.kokoroVoice, speed: settings.kokoroSpeed)
        case .chatterbox:
            return await ChatterboxVoice.render(text)
        case .openAICompatible:
            return await OpenAITTSVoice.render(text, session: Self.urlSession)
        case .elevenLabs:
            return await renderElevenLabsFile(text)
        }
    }

    private var fileQueue: [URL] = []
    private var filePump: Task<Void, Never>?
    /// When the audio for the line now playing was first ready. Speech-start is measured to this, not to the end of playback.
    private var audioReadyAt: Date?

    private func enqueueWAV(_ url: URL) {
        fileQueue.append(url)
        guard filePump == nil else { return }
        filePump = Task { [weak self] in
            while let self, !Task.isCancelled, !self.fileQueue.isEmpty {
                let next = self.fileQueue.removeFirst()
                await VoiceWAVPlayback.play(url: next)
                try? FileManager.default.removeItem(at: next)
            }
            self?.filePump = nil
        }
    }

    private func speakKokoroFile(_ text: String, voice: String, speed: Double, began: Date) async -> Bool {
        guard Date().timeIntervalSince(began) < VoiceTTSChain.firstAudioTimeout + 30 else { return false }
        guard let url = await KokoroVoice.render(text, voice: voice, speed: speed) else { return false }
        if Date().timeIntervalSince(began) > VoiceTTSChain.firstAudioTimeout {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        VoiceLog.log("kokoro", "voice=\(voice) speed=\(speed)")
        markAudioReady()
        enqueueWAV(url)
        return true
    }

    private func speakChatterbox(_ text: String, began: Date) async -> Bool {
        guard let url = await ChatterboxVoice.render(text) else { return false }
        if Date().timeIntervalSince(began) > VoiceTTSChain.firstAudioTimeout {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        VoiceLog.log("chatterbox", "reference clip clone")
        markAudioReady()
        enqueueWAV(url)
        return true
    }

    private func speakOpenAI(_ text: String, began: Date) async -> Bool {
        guard let url = await OpenAITTSVoice.render(text, session: Self.urlSession) else { return false }
        if Date().timeIntervalSince(began) > VoiceTTSChain.firstAudioTimeout {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        VoiceLog.log("openai-tts", VoiceProviderKeychain.logLine(present: true))
        markAudioReady()
        enqueueWAV(url)
        return true
    }

    private func speakElevenLabs(_ text: String, began: Date) async -> Bool {
        guard let route = eleven else { return false }
        var gotAudio = false
        let deadline = began.addingTimeInterval(VoiceTTSChain.firstAudioTimeout)
        do {
            let (bytes, response) = try await Self.urlSession.bytes(for: route.request(for: text))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                var body = Data()
                for try await byte in bytes { body.append(byte); if body.count > 8_192 { break } }
                if ElevenLabsVoice.isKeyRejection(http.statusCode) {
                    VoiceSettings.shared.noteElevenLabsKeyRejected(status: http.statusCode, body: body)
                    VoiceLog.log("kokoro", "fallback \(ElevenLabsVoice.offlineKokoroVoice) \(ElevenLabsVoice.offlineKokoroSpeed) after HTTP \(http.statusCode)")
                }
                return false
            }
            var chunk = Data()
            chunk.reserveCapacity(4_800)
            for try await byte in bytes {
                if Task.isCancelled { return gotAudio }
                if !gotAudio, Date() > deadline { return false }
                chunk.append(byte)
                if chunk.count >= 4_800 {
                    if !gotAudio { markAudioReady() }
                    player.enqueue(chunk)
                    chunk.removeAll(keepingCapacity: true)
                    gotAudio = true
                }
            }
            if !chunk.isEmpty {
                if !gotAudio { markAudioReady() }
                player.enqueue(chunk)
                gotAudio = true
            }
        } catch {
            return gotAudio
        }
        await player.drained()
        return gotAudio
    }

    private func renderElevenLabsFile(_ text: String) async -> URL? {
        guard let route = eleven else { return nil }
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

    func stop() {
        fileQueue.removeAll()
        filePump?.cancel()
        filePump = nil
        queue.removeAll()
        pump?.cancel()
        pump = nil
        pumpToken = nil
        player.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speakWithSystem(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.systemRate
        markAudioReady()
        logSpoken(engine: "system", voice: voice?.name ?? "default")
        NSLog("[ZEUS] voice: engine=system voice=%@ chars=%d", voice.map { "\($0.name) \(Self.qualityName($0.quality))" } ?? "default", text.count)
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    /// Premium > enhanced > default, preferring the exact locale (e.g. en-US over en-GB).
    nonisolated static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let language = String(languageCode.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        let exact = languageCode.replacingOccurrences(of: "_", with: "-")
        return candidates.max { a, b in
            let aScore = a.quality.rawValue * 10 + (a.language == exact ? 1 : 0)
            let bScore = b.quality.rawValue * 10 + (b.language == exact ? 1 : 0)
            return aScore < bScore
        } ?? AVSpeechSynthesisVoice(language: languageCode)
    }
}
