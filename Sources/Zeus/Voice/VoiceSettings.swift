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
        // Only a person picking an engine in Settings reaches this (init assignments do not): that is an explicit choice.
        didSet {
            defaults.set(ttsProvider.rawValue, forKey: "voice.ttsProvider")
            engineAuto = false
        }
    }
    /// Automatic (the default): the local voice, then the Mac voice. A saved key does not add a cloud.
    /// Off only after the owner picks one engine; an install that never changed it stays automatic.
    var engineAuto: Bool { didSet { defaults.set(engineAuto, forKey: "voice.engine.auto") } }
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
    /// A network error or first-audio timeout pauses it for a minute in memory only, so Kokoro takes the rest
    /// of that reply and the next few; a refused request is persisted (`ElevenLabsPause`).
    private var elevenLabsPause: ElevenLabsPause {
        didSet { defaults.set(elevenLabsPause.persistedUntil, forKey: "voice.elevenlabs.pausedUntil") }
    }
    var elevenLabsPausedUntil: Date? { elevenLabsPause.persistedUntil }
    var openAIKeyDraft = ""
    private(set) var openAIKeySaved: Bool
    var geminiKeyDraft = ""
    private(set) var geminiKeySaved: Bool
    /// The voice names the OpenAI and Gemini pickers write (`voice.openai.voice`, `voice.gemini.voice`).
    var openAIVoice: String { didSet { defaults.set(openAIVoice, forKey: "voice.openai.voice") } }
    var geminiVoice: String { didSet { defaults.set(geminiVoice, forKey: "voice.gemini.voice") } }
    var openAIBaseURL: String? { UserDefaults.standard.string(forKey: "voice.openai.baseURL") }
    var openAIModel: String { UserDefaults.standard.string(forKey: "voice.openai.model") ?? UltronCloudVoice.openAIModel }
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
    /// "Studio" (multilingual v2, the default, expressive) or "Fastest" (ElevenLabs flash, lowest delay).
    var elevenQuality: ElevenLabsQuality = .resolve(stored: UserDefaults.standard.string(forKey: ElevenLabsQuality.defaultsKey)) {
        didSet { defaults.set(elevenQuality.rawValue, forKey: ElevenLabsQuality.defaultsKey) }
    }
    /// The result of the quick check after "Save key": a plain line, never the key.
    private(set) var keyCheckMessage: String?
    private(set) var keyCheckOK: Bool?
    private(set) var checkingKey = false
    /// The one-time hint to install an Enhanced or Premium Mac voice. Dismissed by its button.
    var macVoiceHintDismissed: Bool = UserDefaults.standard.bool(forKey: "voice.macVoiceHint.dismissed") {
        didSet { defaults.set(macVoiceHintDismissed, forKey: "voice.macVoiceHint.dismissed") }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "voice.engine").flatMap(VoiceEngine.init(rawValue:))
        // Files only here: the Python import probe runs off the main thread right after init.
        let kokoroSetUp = KokoroWorker.modelFilesPresent()
        let userSelected = UserDefaults.standard.bool(forKey: "voice.engine.userSelected")
        let pausedUntil = UserDefaults.standard.object(forKey: "voice.elevenlabs.pausedUntil") as? Date
        let keyValid = Keychain.get("elevenlabs.api-key") != nil && !UltronVoicePlan.isPaused(until: pausedUntil, now: Date())
        // The default is the local voice. A saved cloud key is not a pick. Only an explicit
        // owner choice (`voice.engine.userSelected` or a provider in Settings) overrides that.
        engine = Self.engine(UltronVoicePlan.initialEngine(
            stored: stored.map(Self.plan), userSelected: userSelected, kokoroReady: kokoroSetUp, elevenLabsKeyValid: keyValid))
        if let raw = UserDefaults.standard.string(forKey: "voice.ttsProvider"),
           let provider = VoiceTTSProvider(rawValue: raw) {
            ttsProvider = provider
        } else {
            ttsProvider = UltronVoicePlan.defaultProvider(kokoroReady: kokoroSetUp, elevenLabsKeyValid: keyValid)
        }
        personality = ZeusPersonality.current()
        engineAuto = ElevenLabsFailsafe.defaultEngineAuto(
            explicit: UserDefaults.standard.object(forKey: "voice.engine.auto") as? Bool,
            storedProvider: UserDefaults.standard.string(forKey: "voice.ttsProvider"))
        kokoroVoice = UserDefaults.standard.string(forKey: "voice.kokoro.voice") ?? ElevenLabsVoice.offlineKokoroVoice
        kokoroSpeed = UserDefaults.standard.object(forKey: "voice.kokoro.speed") as? Double ?? ElevenLabsVoice.offlineKokoroSpeed
        elevenKeySaved = Keychain.get("elevenlabs.api-key") != nil
        openAIKeySaved = Keychain.get("openai-tts.api-key") != nil
        geminiKeySaved = Keychain.get("gemini-tts.api-key") != nil
        openAIVoice = UserDefaults.standard.string(forKey: "voice.openai.voice") ?? UltronCloudVoice.openAIVoice
        geminiVoice = GeminiVoiceCatalog.resolve(stored: UserDefaults.standard.string(forKey: "voice.gemini.voice"))
        kokoroReady = kokoroSetUp
        elevenLabsPause = ElevenLabsPause(persistedUntil: pausedUntil)
        if kokoroSetUp { verifyKokoro() }
    }

    /// Runs the (slow) Python import probe off the main thread and publishes whether Kokoro works.
    func verifyKokoro() {
        Task {
            let ready = await Task.detached { KokoroWorker.isSetUp() }.value
            kokoroReady = ready
        }
    }

    /// OpenAI speech has shut down for the configured model (`OpenAISpeechRetirement`). A saved key and choice stay.
    func openAIRetired(now: Date = Date()) -> Bool { OpenAISpeechRetirement.isRetired(model: openAIModel, baseURL: openAIBaseURL, at: now) }

    func ttsAvailability(elevenLabsPaused: Bool, now: Date = Date()) -> VoiceProviderFallback.Availability {
        VoiceProviderFallback.Availability(
            kokoroReady: kokoroReady,
            chatterboxReady: ChatterboxVoice.isReady,
            elevenLabsConfigured: elevenKeySaved && !elevenLabsPaused,
            openAIConfigured: openAIKeySaved && !openAIRetired(now: now),
            geminiConfigured: geminiKeySaved
        )
    }

    // MARK: Routing (UltronEngineRouter)

    static func engine(for provider: VoiceTTSProvider) -> UltronEngine {
        switch provider {
        case .kokoro: .kokoro
        case .chatterbox: .chatterbox
        case .elevenLabs: .elevenLabs
        case .openAICompatible: .openAI
        case .gemini: .gemini
        case .googleCloud: .system
        }
    }

    func ultronAvailability(now: Date = Date()) -> UltronEngineAvailability {
        UltronEngineAvailability(
            elevenLabsConfigured: ElevenLabsVoice.hasRoute, elevenLabsPaused: isProviderPaused(.elevenLabs, now: now),
            openAIConfigured: openAIKeySaved, openAIPaused: isProviderPaused(.openAICompatible, now: now),
            geminiConfigured: geminiKeySaved, geminiPaused: isProviderPaused(.gemini, now: now),
            kokoroReady: kokoroReady, kokoroPaused: isProviderPaused(.kokoro, now: now),
            chatterboxReady: ChatterboxVoice.isReady, chatterboxPaused: isProviderPaused(.chatterbox, now: now),
            openAIRetired: openAIRetired(now: now))
    }

    var engineChoice: UltronEngineChoice { engineAuto ? .auto : .fixed(Self.engine(for: ttsProvider)) }

    /// Engines to try for the next reply, best first, each with the reason it is in the chain.
    func routeDecisions() -> [UltronRouteDecision] {
        UltronEngineRouter.chain(choice: engineChoice, availability: ultronAvailability(), observedFirstAudioMs: observedFirstAudio())
    }

    /// Smoothed time to first audio per engine, so a slow engine stops leading in automatic mode.
    func observedFirstAudio() -> [UltronEngine: Int] {
        var out: [UltronEngine: Int] = [:]
        for engine in UltronEngine.allCases {
            if let ms = defaults.object(forKey: "voice.firstAudioMs.\(engine.rawValue)") as? Int { out[engine] = ms }
        }
        return out
    }

    func recordFirstAudio(_ engine: UltronEngine, ms: Int) {
        let key = "voice.firstAudioMs.\(engine.rawValue)"
        let previous = defaults.object(forKey: key) as? Int
        defaults.set(previous.map { ($0 * 2 + ms) / 3 } ?? ms, forKey: key)
    }

    func isProviderPaused(_ provider: VoiceTTSProvider, now: Date = Date()) -> Bool {
        if provider == .elevenLabs, elevenLabsPause.isPaused(now: now) { return true }
        let key = "voice.provider.pause.\(provider.rawValue)"
        guard let until = defaults.object(forKey: key) as? Date else { return false }
        return until > now
    }

    func noteProviderFailure(_ provider: VoiceTTSProvider, reason: VoiceTTSChain.FailureReason, now: Date = Date()) {
        var until = now.addingTimeInterval(10 * 60)
        if provider == .elevenLabs {
            let failure: ElevenLabsFailure = (reason == .http401 || reason == .quota) ? .status(401) : .unreachable
            elevenLabsPause.note(failure, now: now)
            until = now.addingTimeInterval(UltronVoicePlan.pauseSeconds(status: failure == .unreachable ? nil : 401))
        } else {
            defaults.set(until, forKey: "voice.provider.pause.\(provider.rawValue)")
        }
        let label = provider.title
        switch reason {
        case .http401:
            fallbackMessage = ProviderFailureMessage.message(label: label, kind: .badKey)
        case .quota:
            fallbackMessage = ProviderFailureMessage.message(label: label, kind: .creditsUsedUp)
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

    func saveGeminiKey() {
        let key = geminiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { geminiKeyDraft = ""; return }
        // A failed Keychain write keeps the draft, so the pasted key is never lost silently.
        guard Keychain.set(key, for: "gemini-tts.api-key") else {
            keyMessage = "Couldn't save the Gemini key to your Keychain. It is still in the field."
            return
        }
        geminiKeyDraft = ""
        keyMessage = nil
        geminiKeySaved = true
        clearProviderPause(.gemini)
    }

    func removeGeminiKey() {
        guard Keychain.remove("gemini-tts.api-key") else {
            keyMessage = "Couldn't remove the Gemini key. Check Keychain access and try again."
            return
        }
        geminiKeySaved = false
        geminiKeyDraft = ""
        keyMessage = nil
        defaults.removeObject(forKey: "voice.provider.pause.gemini")
    }

    // MARK: ElevenLabs

    /// A voice id has been saved (designed or picked): the default voice from then on.
    var hasDesignedVoice: Bool { Keychain.get("elevenlabs.voice-id")?.isEmpty == false }

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
        Task { await validateElevenKey() }
    }

    /// One free metadata call with the saved key: "Key works" or the reason it was refused.
    func validateElevenKey() async {
        guard let key = Keychain.get("elevenlabs.api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        checkingKey = true
        keyCheckMessage = "Checking the key."
        keyCheckOK = nil
        defer { checkingKey = false }
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/models")!, timeoutInterval: 10)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        let result: ElevenLabsKeyCheck.Result
        do {
            let (data, response) = try await Speaker.elevenLabsSession.data(for: request)
            result = ElevenLabsKeyCheck.interpret(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch {
            result = ElevenLabsKeyCheck.unreachable
        }
        keyCheckMessage = result.message
        keyCheckOK = result.ok
        VoiceLog.log("voice", "elevenlabs key check ok=\(result.ok)")
    }

    func removeElevenKey() {
        guard Keychain.remove("elevenlabs.api-key") else {
            keyMessage = "Couldn't remove the ElevenLabs key. Check Keychain access and try again."
            return
        }
        elevenKeySaved = false
        elevenKeyDraft = ""
        keyCheckMessage = nil
        keyCheckOK = nil
        keyMessage = nil
        library = []
        elevenLabsStatusMessage = nil
        elevenLabsPause.clear()
        if engine == .elevenLabs { engine = .system }
    }

    /// A 401/402 means the key itself is bad, not a momentary limit: stop paying the round trip
    /// for 15 minutes. A 429 is a real rate limit, so 60 s is enough to let it clear.
    func noteElevenLabsKeyRejected(status: Int, body: Data) {
        elevenLabsStatusMessage = ElevenLabsVoice.settingsMessage(status: status, body: body)
        ElevenLabsVoice.logKeyRejection(status: status, body: body)
        elevenLabsPause.note(.status(status), now: Date())
    }

    /// Called the moment ElevenLabs actually streams audio again, so a now-working key (or a
    /// transient network blip that wasn't really a rejection) doesn't stay paused needlessly.
    func clearElevenLabsPause() {
        fallbackMessage = nil
        fallbackMessageUntil = nil
        elevenLabsPause.clear()
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

    static func plan(_ engine: VoiceEngine) -> UltronVoicePlan.Engine {
        switch engine {
        case .kokoro: .kokoro
        case .elevenLabs: .elevenLabs
        case .system: .system
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
