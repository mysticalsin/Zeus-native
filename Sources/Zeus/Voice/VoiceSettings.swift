import AVFoundation
import Foundation
import Observation
import ZeusCore

/// Which voice Zeus answers with.
enum VoiceEngine: String, CaseIterable, Identifiable {
    case system, elevenLabs, kokoro
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System voice"
        case .elevenLabs: "ElevenLabs"
        case .kokoro: "Kokoro (on this Mac)"
        }
    }
    var detail: String {
        switch self {
        case .system: "Free, instant and offline. Uses the best voice installed in macOS."
        case .elevenLabs: "A natural cloud voice from the ElevenLabs library. Your text is sent to ElevenLabs."
        case .kokoro: "A natural voice that runs on this Mac. Free, private and offline after setup."
        }
    }
}

/// Voice choices and the ElevenLabs and Kokoro state behind Settings > Voice.
@MainActor
@Observable
final class VoiceSettings {
    static let shared = VoiceSettings()
    private let defaults = UserDefaults.standard

    struct LibraryVoice: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let detail: String
    }

    var engine: VoiceEngine {
        didSet {
            defaults.set(engine.rawValue, forKey: "voice.engine")
            defaults.set(true, forKey: "voice.engine.userSelected")
        }
    }
    var ttsProvider: VoiceTTSProvider {
        didSet { defaults.set(ttsProvider.rawValue, forKey: "voice.ttsProvider") }
    }
    /// How Zeus talks: the prompt's persona section, the instant voice lines and the ElevenLabs delivery.
    var personality: ZeusPersonality { didSet { defaults.set(personality.rawValue, forKey: ZeusPersonality.defaultsKey) } }
    var kokoroVoice: String { didSet { defaults.set(kokoroVoice, forKey: "voice.kokoro.voice") } }
    var kokoroSpeed: Double { didSet { defaults.set(kokoroSpeed, forKey: "voice.kokoro.speed") } }
    var elevenKeyDraft = ""
    private(set) var elevenKeySaved: Bool
    private(set) var library: [LibraryVoice] = []
    private(set) var libraryMessage: String?
    private(set) var settingUpKokoro = false
    private(set) var kokoroReady: Bool
    var kokoroMessage: String?
    private(set) var testing = false
    private(set) var elevenLabsStatusMessage: String?
    /// QA7 round 11: every reply re-tried a persistently rejected ElevenLabs key (401
    /// quota_exceeded), each time paying a network round trip before falling back to Kokoro --
    /// because the old 60 s in-memory pause on `Speaker` routinely expired between one slow
    /// fallback-brain reply and the next (51-57 s apart in that round). Persisted here so the
    /// pause survives both a new `Speaker` instance and a new app launch; cleared when the key
    /// changes or a stream actually succeeds.
    private(set) var elevenLabsPausedUntil: Date? {
        didSet { defaults.set(elevenLabsPausedUntil, forKey: "voice.elevenlabs.pausedUntil") }
    }
    var openAIKeyDraft = ""
    private(set) var openAIKeySaved: Bool
    private var fallbackMessage: String?
    /// The fallback notice stays only while the pause behind it lasts (and until a provider works again).
    private var fallbackMessageUntil: Date?
    var lastProviderFallbackMessage: String? {
        guard let until = fallbackMessageUntil, until > Date() else { return nil }
        return fallbackMessage
    }
    private(set) var loadingLibrary = false
    /// A key that could not be saved, or a preview that was written to a file instead of played.
    var keyMessage: String?
    var previewMessage: String?

    private init() {
        let stored = UserDefaults.standard.string(forKey: "voice.engine").flatMap(VoiceEngine.init(rawValue:))
        // Files only here: the Python import probe runs off the main thread right after init.
        let kokoroSetUp = KokoroWorker.modelFilesPresent()
        let userSelected = UserDefaults.standard.bool(forKey: "voice.engine.userSelected")
        let pausedUntil = UserDefaults.standard.object(forKey: "voice.elevenlabs.pausedUntil") as? Date
        let keyValid = Keychain.get("elevenlabs.api-key") != nil && (pausedUntil.map { $0 <= Date() } ?? true)
        // Ultron is the local voice first. ElevenLabs is used only when its key is valid and Kokoro
        // is not ready. A stored ElevenLabs choice that the person never confirmed follows that order,
        // so a 401 key is not the voice that answers. An explicit choice still wins.
        let preferred = Self.engine(UltronVoicePlan.preferred(kokoroReady: kokoroSetUp, elevenLabsKeyValid: keyValid))
        if let stored, (userSelected || stored == .kokoro) {
            engine = stored
        } else {
            engine = preferred
        }
        if let raw = UserDefaults.standard.string(forKey: "voice.ttsProvider"),
           let provider = VoiceTTSProvider(rawValue: raw) {
            ttsProvider = provider
        } else if kokoroSetUp || !keyValid {
            // Ultron default: the free local engine. ElevenLabs only when a key is present and not paused.
            ttsProvider = .kokoro
        } else {
            ttsProvider = .elevenLabs
        }
        personality = ZeusPersonality.current()
        kokoroVoice = UserDefaults.standard.string(forKey: "voice.kokoro.voice") ?? ElevenLabsVoice.offlineKokoroVoice
        kokoroSpeed = UserDefaults.standard.object(forKey: "voice.kokoro.speed") as? Double ?? ElevenLabsVoice.offlineKokoroSpeed
        elevenKeySaved = Keychain.get("elevenlabs.api-key") != nil
        openAIKeySaved = Keychain.get("openai-tts.api-key") != nil
        kokoroReady = kokoroSetUp
        elevenLabsPausedUntil = UserDefaults.standard.object(forKey: "voice.elevenlabs.pausedUntil") as? Date
        if kokoroSetUp { verifyKokoro() }
    }

    /// Runs the (slow) Python import probe off the main thread and publishes whether Kokoro works.
    func verifyKokoro() {
        Task {
            let ready = await Task.detached { KokoroWorker.isSetUp() }.value
            kokoroReady = ready
        }
    }

    func ttsAvailability(elevenLabsPaused: Bool) -> VoiceProviderFallback.Availability {
        VoiceProviderFallback.Availability(
            kokoroReady: kokoroReady,
            chatterboxReady: ChatterboxVoice.isReady,
            elevenLabsConfigured: elevenKeySaved && !elevenLabsPaused,
            openAIConfigured: openAIKeySaved
        )
    }

    func isProviderPaused(_ provider: VoiceTTSProvider, now: Date = Date()) -> Bool {
        if provider == .elevenLabs, let until = elevenLabsPausedUntil, until > now { return true }
        let key = "voice.provider.pause.\(provider.rawValue)"
        guard let until = defaults.object(forKey: key) as? Date else { return false }
        return until > now
    }

    func noteProviderFailure(_ provider: VoiceTTSProvider, reason: VoiceTTSChain.FailureReason, now: Date = Date()) {
        let until = now.addingTimeInterval(10 * 60)
        if provider == .elevenLabs {
            if reason == .http401 || reason == .quota {
                elevenLabsPausedUntil = until
            }
        } else {
            defaults.set(until, forKey: "voice.provider.pause.\(provider.rawValue)")
        }
        let label = provider.title
        switch reason {
        case .http401, .quota:
            fallbackMessage = "\(label): quota exceeded, using next voice"
        case .timeout:
            fallbackMessage = "\(label): timed out, using next voice"
        case .missingModel:
            fallbackMessage = "\(label): model missing, using next voice"
        case .offline, .other:
            fallbackMessage = "\(label): unavailable, using next voice"
        }
        fallbackMessageUntil = until
    }

    func clearProviderPause(_ provider: VoiceTTSProvider) {
        fallbackMessage = nil
        fallbackMessageUntil = nil
        defaults.removeObject(forKey: "voice.provider.pause.\(provider.rawValue)")
        if provider == .elevenLabs { clearElevenLabsPause() }
    }

    func saveOpenAIKey() {
        let key = openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { openAIKeyDraft = ""; return }
        // A failed Keychain write keeps the draft, so the pasted key is never lost silently.
        guard Keychain.set(key, for: "openai-tts.api-key") else {
            keyMessage = "Couldn't save the OpenAI TTS key to your Keychain. It is still in the field."
            return
        }
        openAIKeyDraft = ""
        keyMessage = nil
        openAIKeySaved = true
        clearProviderPause(.openAICompatible)
    }

    func removeOpenAIKey() {
        guard Keychain.remove("openai-tts.api-key") else {
            keyMessage = "Couldn't remove the OpenAI TTS key. Check Keychain access and try again."
            return
        }
        openAIKeySaved = false
        openAIKeyDraft = ""
        keyMessage = nil
        defaults.removeObject(forKey: "voice.provider.pause.openAICompatible")
    }

    // MARK: ElevenLabs

    var elevenVoiceID: String { Keychain.get("elevenlabs.voice-id") ?? ElevenLabsVoice.defaultVoiceID }

    func setElevenVoice(_ id: String) {
        let clean = id.filter { $0.isLetter || $0.isNumber }
        let saved = clean.isEmpty ? Keychain.remove("elevenlabs.voice-id") : Keychain.set(clean, for: "elevenlabs.voice-id")
        keyMessage = saved ? nil : "Couldn't update the saved voice. Check Keychain access and try again."
    }

    func saveElevenKey() {
        let key = elevenKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { elevenKeyDraft = ""; return }
        guard Keychain.set(key, for: "elevenlabs.api-key") else {
            keyMessage = "Couldn't save the ElevenLabs key to your Keychain. It is still in the field."
            return
        }
        elevenKeyDraft = ""
        keyMessage = nil
        elevenKeySaved = true
        library = []
        libraryMessage = nil
        clearElevenLabsPause()
    }

    func removeElevenKey() {
        guard Keychain.remove("elevenlabs.api-key") else {
            keyMessage = "Couldn't remove the ElevenLabs key. Check Keychain access and try again."
            return
        }
        elevenKeySaved = false
        elevenKeyDraft = ""
        keyMessage = nil
        library = []
        elevenLabsStatusMessage = nil
        elevenLabsPausedUntil = nil
        if engine == .elevenLabs { engine = .system }
    }

    /// A 401/402 means the key itself is bad, not a momentary limit: stop paying the round trip
    /// for 15 minutes. A 429 is a real rate limit, so 60 s is enough to let it clear.
    func noteElevenLabsKeyRejected(status: Int, body: Data) {
        elevenLabsStatusMessage = ElevenLabsVoice.settingsMessage(status: status, body: body)
        ElevenLabsVoice.logKeyRejection(status: status, body: body)
        let pause: TimeInterval = (status == 401 || status == 402) ? 15 * 60 : 60
        elevenLabsPausedUntil = Date().addingTimeInterval(pause)
    }

    /// Called the moment ElevenLabs actually streams audio again, so a now-working key (or a
    /// transient network blip that wasn't really a rejection) doesn't stay paused needlessly.
    func clearElevenLabsPause() {
        fallbackMessage = nil
        fallbackMessageUntil = nil
        elevenLabsPausedUntil = nil
        elevenLabsStatusMessage = nil
    }

    /// The voices on the account, including the ElevenLabs library voices added to it.
    func loadLibrary() async {
        guard !loadingLibrary else { return }
        guard let key = Keychain.get("elevenlabs.api-key") else { libraryMessage = "Save your ElevenLabs key first."; return }
        loadingLibrary = true
        defer { loadingLibrary = false }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        libraryMessage = "Loading voices."
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { libraryMessage = "ElevenLabs refused the key."; return }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let voices = (json?["voices"] as? [[String: Any]] ?? []).compactMap { item -> LibraryVoice? in
                guard let id = item["voice_id"] as? String, let name = item["name"] as? String else { return nil }
                let labels = item["labels"] as? [String: String] ?? [:]
                let detail = [labels["accent"], labels["gender"], labels["descriptive"]].compactMap { $0 }.joined(separator: ", ")
                return LibraryVoice(id: id, name: name, detail: detail)
            }
            library = voices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            libraryMessage = voices.isEmpty ? "No voices on this account yet." : nil
        } catch {
            libraryMessage = "Could not reach ElevenLabs."
        }
    }

    // MARK: Kokoro

    func setUpKokoro() {
        guard !settingUpKokoro else { return }
        settingUpKokoro = true
        kokoroMessage = "Setting up Kokoro. The first run downloads about 350 MB."
        Task {
            // Pressing Set up is the only place Kokoro touches the network: packages, then the two model files.
            let installFailure = await Task.detached { LocalPython.install(KokoroWorker.pythonPackages) }.value
            if let installFailure {
                finishKokoroSetup(ready: false, message: installFailure)
                return
            }
            // Files already on this Mac (including a chosen folder) are used as they are.
            let dir = KokoroWorker.modelFilesPresent() ? KokoroWorker.modelDir() : KokoroWorker.managedModelDir
            if let downloadFailure = await KokoroWorker.downloadModelFiles(to: dir) {
                finishKokoroSetup(ready: false, message: downloadFailure)
                return
            }
            // The import probe caches its answer, so forget the pre-install "no" before re-checking.
            let loads = await Task.detached { () -> Bool in
                KokoroWorker.resetImportProbe()
                let python = KokoroWorker.pythonExecutable()
                return KokoroWorker.kokoroOnnxImportWorks(python: python) && KokoroWorker.modelLoads(python: python, modelDir: dir)
            }.value
            guard loads else {
                finishKokoroSetup(ready: false, message: "Kokoro installed, but it could not load its model files in \(dir.path). Run Set up again, or remove them and retry.")
                return
            }
            defaults.set(dir.path, forKey: "voice.kokoro.modelDir")
            let ready = await Task.detached { KokoroWorker.isSetUp() }.value
            finishKokoroSetup(ready: ready, message: ready ? nil : "Kokoro loaded its files but is still not ready. Quit and reopen Zeus, then try again.")
        }
    }

    private func finishKokoroSetup(ready: Bool, message: String?) {
        settingUpKokoro = false
        kokoroReady = ready
        kokoroMessage = message
    }

    /// Plays one line: the person pressed Preview, so it is heard. Only the silent test harness
    /// (`ZEUS_SILENT_TESTS=1`, or `AUDIBLE-OK` set to 0/false) writes a WAV instead, and the page says so.
    func test(with speaker: Speaker) {
        let line = "Good evening. Everything is in order, and I am ready when you are."
        let env = ProcessInfo.processInfo.environment
        let audibleOK = (env["AUDIBLE-OK"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let silent = env["ZEUS_SILENT_TESTS"] == "1" || audibleOK == "0" || audibleOK == "false"
        previewMessage = nil
        if silent {
            Task {
                let dir = QuietHoursVoiceTest.outputDirectory()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent("provider-\(ttsProvider.rawValue)-\(Int(Date().timeIntervalSince1970)).wav")
                let ok = await speaker.renderTestLine(line, to: file)
                if ok {
                    previewMessage = "Silent mode is on. The preview was saved to \(file.path) instead of played."
                } else {
                    let note = dir.appendingPathComponent("provider-\(ttsProvider.rawValue)-\(Int(Date().timeIntervalSince1970)).txt")
                    try? "Saved, not played (silent mode)\n\(line)".write(to: note, atomically: true, encoding: .utf8)
                    previewMessage = "Silent mode is on. Nothing was played; a note was saved in \(dir.path)."
                }
            }
            return
        }
        testing = true
        speaker.stop()
        speaker.speak(line)
        Task {
            try? await Task.sleep(for: .seconds(1))
            while speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(300)) }
            testing = false
        }
    }

    static func engine(_ plan: UltronVoicePlan.Engine) -> VoiceEngine {
        switch plan {
        case .kokoro: .kokoro
        case .elevenLabs: .elevenLabs
        case .system: .system
        }
    }

    static let kokoroVoices: [(id: String, name: String)] = [
        ("bm_george", "George, British, deep"), ("bm_lewis", "Lewis, British"), ("bm_daniel", "Daniel, British"),
        ("am_michael", "Michael, American, deep"), ("am_adam", "Adam, American"), ("am_eric", "Eric, American"),
        ("bf_emma", "Emma, British"), ("af_heart", "Heart, American"), ("af_bella", "Bella, American"),
    ]
}

/// Kokoro text to speech via kokoro_onnx resident worker (read-only model dir on disk).
enum KokoroVoice {
    /// The WAV for `text`, or nil when Kokoro could not make it.
    static func render(_ text: String, voice: String, speed: Double) async -> URL? {
        await KokoroWorkerSession.shared.render(text, voice: voice, speed: speed)
    }
}
