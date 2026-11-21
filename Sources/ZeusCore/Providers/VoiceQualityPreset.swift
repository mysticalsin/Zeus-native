import Foundation

/// Typed failures for the quality-preset path. Descriptions name the failure only.
/// A key, a response body, and a URL are never part of the text.
public enum VoiceQualityError: Error, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case voiceRefused
    case providerOff
    case meterExceeded
    case meterCorrupt
    case missingCredential

    public var description: String {
        switch self {
        case .voiceRefused: "voice refused"
        case .providerOff: "provider is off"
        case .meterExceeded: "character meter exceeded"
        case .meterCorrupt: "character meter unreadable"
        case .missingCredential: "missing credential"
        }
    }

    public var debugDescription: String { description }

    public static func publicError(_ error: Error) -> Error {
        if error is CancellationError { return ProviderFailure.cancelled }
        if error is VoiceQualityError { return error }
        if error is ProviderFailure { return error }
        return ProviderFailure.wrap(error)
    }

    public static func publicName(_ error: Error) -> String {
        let surfaced = publicError(error)
        if let failure = surfaced as? ProviderFailure { return failure.logName }
        if let quality = surfaced as? VoiceQualityError { return quality.description }
        return "invalid-response"
    }
}

/// One stock voice that is allowed on a cloud request. `reason` says why the id is generic.
public struct StockVoice: Equatable, Sendable {
    public var id: String
    public var name: String
    public var reason: String

    public init(id: String, name: String, reason: String) {
        self.id = id
        self.name = name
        self.reason = reason
    }
}

/// Explicit stock voices. Anything else is refused, including Voice Library ids, clones,
/// character names, and any id that contains "MCU".
public enum VoiceQualityAllowList {
    /// ElevenLabs premade default voices (the account default list, not the Voice Library).
    /// Each name is a generic stock label. Legacy character voices (Glinda) and celebrity-coded
    /// names (Arnold) are left out, as are library replacements such as "Eldrin".
    public static let elevenLabs: [StockVoice] = [
        StockVoice(
            id: "EXAVITQu4vr4xnSDxMaL",
            name: "Sarah",
            reason: "ElevenLabs default premade voice. Generic first name, not a named person, actor, or character."
        ),
        StockVoice(
            id: "JBFqnCBsd6RMkjVDRZzb",
            name: "George",
            reason: "ElevenLabs default premade voice. Generic first name. This is the stock id already used when no designed voice is saved."
        ),
        StockVoice(
            id: "IKne3meq5aSn9XLyUdCD",
            name: "Charlie",
            reason: "ElevenLabs default premade voice. Generic first name, not a named person, actor, or character."
        ),
        StockVoice(
            id: "pNInz6obpgDQGcFmaJgB",
            name: "Adam",
            reason: "ElevenLabs default premade voice. Generic first name, not a named person, actor, or character."
        ),
    ]

    /// Google Cloud stock voices: Neural2, WaveNet, or Chirp HD only.
    /// Letter labels and star catalog names are generic. Myth and character names (Puck, Fenrir) are not listed.
    public static let google: [StockVoice] = [
        StockVoice(
            id: "en-US-Neural2-C",
            name: "Neural2 C",
            reason: "Google Neural2 stock voice. The id is a letter label, not a person or character."
        ),
        StockVoice(
            id: "en-US-Neural2-D",
            name: "Neural2 D",
            reason: "Google Neural2 stock voice. The id is a letter label, not a person or character."
        ),
        StockVoice(
            id: "en-US-Wavenet-D",
            name: "Wavenet D",
            reason: "Google WaveNet stock voice, official id en-US-Wavenet-D. Letter label, not a person or character."
        ),
        StockVoice(
            id: "en-US-Wavenet-F",
            name: "Wavenet F",
            reason: "Google WaveNet stock voice, official id en-US-Wavenet-F. Letter label, not a person or character."
        ),
        StockVoice(
            id: "en-US-Chirp-HD-D",
            name: "Chirp HD D",
            reason: "Google Chirp HD stock voice. Letter label, not a person, actor, or film character."
        ),
        StockVoice(
            id: "en-US-Chirp3-HD-Achernar",
            name: "Chirp3 HD Achernar",
            reason: "Google Chirp 3 HD stock voice named for the star Achernar. Not a person, actor, or film character."
        ),
        StockVoice(
            id: "en-US-Chirp3-HD-Alnilam",
            name: "Chirp3 HD Alnilam",
            reason: "Google Chirp 3 HD stock voice named for the star Alnilam. Not a person, actor, or film character."
        ),
    ]

    public static func accepts(_ voiceID: String, providerID: String) -> Bool {
        let trimmed = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: "mcu", options: .caseInsensitive) != nil { return false }
        let list: [StockVoice]
        switch providerID {
        case ElevenLabsTTSAdapter.id: list = elevenLabs
        case GoogleCloudTTSAdapter.id: list = google
        default: return false
        }
        return list.contains { $0.id == trimmed }
    }
}

/// ElevenLabs model, stability, and style for one quality preset.
public struct ElevenLabsQualityDelivery: Equatable, Sendable {
    public var modelID: String
    public var stability: Double
    public var style: Double

    public init(modelID: String, stability: Double, style: Double) {
        self.modelID = modelID
        self.stability = stability
        self.style = style
    }
}

/// Google voice, speaking rate, pitch, and 24 kHz encoding for one quality preset.
public struct GoogleQualityDelivery: Equatable, Sendable {
    public var voiceID: String
    public var speakingRate: Double
    public var pitch: Double
    public var audioEncoding: String
    public var sampleRateHertz: Int
    /// Chirp 3 HD rejects speaking rate and pitch. The preset still records the chosen values.
    /// The request omits those two fields when this is false.
    public var sendsRateAndPitch: Bool

    public init(voiceID: String, speakingRate: Double, pitch: Double, audioEncoding: String, sampleRateHertz: Int, sendsRateAndPitch: Bool) {
        self.voiceID = voiceID
        self.speakingRate = speakingRate
        self.pitch = pitch
        self.audioEncoding = audioEncoding
        self.sampleRateHertz = sampleRateHertz
        self.sendsRateAndPitch = sendsRateAndPitch
    }
}

/// Opt-in quality presets. They are off until the user picks both the provider and a preset.
/// The speak-path default stays `zeus.synthetic`.
public enum VoiceQualityPreset: String, Sendable, CaseIterable, Equatable {
    case elevenLabsFast
    case elevenLabsStudio
    case googleNeural2
    case googleWavenet
    case googleChirpHD

    public var providerID: String {
        switch self {
        case .elevenLabsFast, .elevenLabsStudio: ElevenLabsTTSAdapter.id
        case .googleNeural2, .googleWavenet, .googleChirpHD: GoogleCloudTTSAdapter.id
        }
    }

    public var defaultVoiceID: String {
        switch self {
        case .elevenLabsFast: "EXAVITQu4vr4xnSDxMaL"
        case .elevenLabsStudio: "JBFqnCBsd6RMkjVDRZzb"
        case .googleNeural2: "en-US-Neural2-D"
        case .googleWavenet: "en-US-Wavenet-D"
        case .googleChirpHD: "en-US-Chirp3-HD-Achernar"
        }
    }

    /// Fast uses `eleven_flash_v2_5`. Stability 0.45 and style 0 match the existing plain delivery:
    /// a steady read, with pauses carried by punctuation rather than extra style.
    /// Studio uses `eleven_multilingual_v2`. Stability 0.6 and style 0.3 are take C
    /// (`UltronCloudVoice.elevenLabsSettings`): fewer breaths, still no SSML.
    public var elevenLabs: ElevenLabsQualityDelivery? {
        switch self {
        case .elevenLabsFast:
            return ElevenLabsQualityDelivery(modelID: "eleven_flash_v2_5", stability: 0.45, style: 0)
        case .elevenLabsStudio:
            let settings = UltronCloudVoice.elevenLabsSettings
            return ElevenLabsQualityDelivery(
                modelID: "eleven_multilingual_v2",
                stability: settings["stability"] ?? 0.6,
                style: settings["style"] ?? 0.3
            )
        case .googleNeural2, .googleWavenet, .googleChirpHD:
            return nil
        }
    }

    /// Neural2 uses speaking rate 0.92, the measured pace already used for the Mac voice, and pitch 0.
    /// WaveNet and Chirp HD stay at rate 1 and pitch 0 so the stock voice is not shifted.
    /// Every Google preset asks for LINEAR16 at 24 kHz. Chirp HD does not send rate or pitch:
    /// Google rejects those fields on Chirp 3 HD.
    public var google: GoogleQualityDelivery? {
        switch self {
        case .googleNeural2:
            return GoogleQualityDelivery(voiceID: defaultVoiceID, speakingRate: 0.92, pitch: 0, audioEncoding: "LINEAR16", sampleRateHertz: 24_000, sendsRateAndPitch: true)
        case .googleWavenet:
            return GoogleQualityDelivery(voiceID: defaultVoiceID, speakingRate: 1, pitch: 0, audioEncoding: "LINEAR16", sampleRateHertz: 24_000, sendsRateAndPitch: true)
        case .googleChirpHD:
            return GoogleQualityDelivery(voiceID: defaultVoiceID, speakingRate: 1, pitch: 0, audioEncoding: "LINEAR16", sampleRateHertz: 24_000, sendsRateAndPitch: false)
        case .elevenLabsFast, .elevenLabsStudio:
            return nil
        }
    }
}

public enum VoiceQualitySelection: Equatable, Sendable {
    case synthetic
    case preset(VoiceQualityPreset)
}

/// Providers stay off unless `voice.ttsProvider` names ElevenLabs or Google Cloud and
/// `voice.quality.preset` names a preset for that same provider. Otherwise the voice is `zeus.synthetic`.
public enum VoiceQualityOptIn {
    public static let presetKey = "voice.quality.preset"

    public static func selection(defaults: UserDefaults) -> VoiceQualitySelection {
        let choice = VoiceProviderAccounts.choice(fromTTSProvider: defaults.string(forKey: VoiceProviderPreferences.selectionKey))
        guard case .provider(let id) = choice,
              let raw = defaults.string(forKey: presetKey),
              let preset = VoiceQualityPreset(rawValue: raw),
              preset.providerID == id else { return .synthetic }
        return .preset(preset)
    }

    public static func activeVoiceID(defaults: UserDefaults) -> String {
        switch selection(defaults: defaults) {
        case .synthetic: VoiceSpeakAllowlist.syntheticID
        case .preset(let preset): preset.defaultVoiceID
        }
    }
}

/// Pause marks stay the existing ellipsis sanitizer. Untrusted text is not wrapped in SSML.
public enum VoiceQualityMarkup {
    public static func spoken(_ text: String) -> String {
        UltronSpeechText.sanitize(text)
    }
}

/// A request with a description that names the method and host only. Headers, including the key, are omitted.
public struct VoiceQualityCall: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var request: ProviderHTTPRequest

    public init(request: ProviderHTTPRequest) { self.request = request }

    public var description: String {
        "\(request.method) \(request.url.host ?? "-")\(request.url.path)"
    }

    public var debugDescription: String { description }
}

public enum VoiceQualityRequestBuilder {
    public static func make(text: String, preset: VoiceQualityPreset, voiceID: String, credential: ProviderCredential) throws -> ProviderHTTPRequest {
        guard VoiceQualityAllowList.accepts(voiceID, providerID: preset.providerID) else {
            throw VoiceQualityError.voiceRefused
        }
        guard let key = credential.value(ProviderCredentialLocation.account) else {
            throw VoiceQualityError.missingCredential
        }
        let spoken = VoiceQualityMarkup.spoken(text)
        switch preset {
        case .elevenLabsFast, .elevenLabsStudio:
            guard let delivery = preset.elevenLabs else { throw VoiceQualityError.voiceRefused }
            return try elevenLabs(spoken, voiceID: voiceID, delivery: delivery, key: key)
        case .googleNeural2, .googleWavenet, .googleChirpHD:
            guard let delivery = preset.google else { throw VoiceQualityError.voiceRefused }
            return try google(spoken, voiceID: voiceID, delivery: delivery, key: key)
        }
    }

    private static func elevenLabs(_ text: String, voiceID: String, delivery: ElevenLabsQualityDelivery, key: String) throws -> ProviderHTTPRequest {
        guard let voice = ElevenLabsTTSAdapter.pathComponent(voiceID),
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw VoiceQualityError.voiceRefused
        }
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
        guard let streaming = components.url,
              let body = ProviderJSON.data([
                "text": text,
                "model_id": delivery.modelID,
                "voice_settings": [
                    "stability": delivery.stability,
                    "style": delivery.style,
                ],
              ]) else { throw VoiceQualityError.voiceRefused }
        return ProviderHTTPRequest(
            url: streaming,
            method: "POST",
            headers: [
                "xi-api-key": key,
                "Content-Type": "application/json",
                "Accept": "audio/pcm",
            ],
            body: body
        )
    }

    private static func google(_ text: String, voiceID: String, delivery: GoogleQualityDelivery, key: String) throws -> ProviderHTTPRequest {
        guard let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize") else {
            throw VoiceQualityError.voiceRefused
        }
        var audio: [String: Any] = [
            "audioEncoding": delivery.audioEncoding,
            "sampleRateHertz": delivery.sampleRateHertz,
        ]
        if delivery.sendsRateAndPitch {
            audio["speakingRate"] = delivery.speakingRate
            audio["pitch"] = delivery.pitch
        }
        let voice = ProviderVoice(id: voiceID, name: voiceID, language: nil)
        guard let body = ProviderJSON.data([
            "input": ["text": text],
            "voice": [
                "languageCode": GoogleCloudTTSAdapter.languageCode(for: voice),
                "name": voiceID,
            ],
            "audioConfig": audio,
        ]) else { throw VoiceQualityError.voiceRefused }
        return ProviderHTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "X-Goog-Api-Key": key,
                "Content-Type": "application/json",
            ],
            body: body
        )
    }
}

/// Reads a provider key from the seam's credential store. On macOS that store is
/// `KeychainCredentialStore` (generic password, this device only) under `com.zeus.app`.
/// The key is not written to UserDefaults, the meter file, logs, or error text.
public enum VoiceQualityKeychain {
    public static func credential(providerID: String, store: any CredentialStore) -> ProviderCredential? {
        guard let key = store.read(service: VoiceProviderAccounts.service, account: VoiceProviderAccounts.keyAccount(for: providerID)),
              VoiceProviderKeyPolicy.accepts(key) else { return nil }
        return ProviderCredential(fields: [ProviderCredentialLocation.account: key])
    }
}

/// How `VoiceProviderSession.fallback` already treats these failures.
/// Kokoro, then the Mac voice. A 401 or 429 leaves the provider in error. A 5xx leaves it ready.
public struct VoiceQualityFallbackPlan: Equatable, Sendable {
    public var engines: [String]
    public var leavesProviderReady: Bool

    public init(engines: [String], leavesProviderReady: Bool) {
        self.engines = engines
        self.leavesProviderReady = leavesProviderReady
    }
}

public enum VoiceQualityFallback {
    public static func plan(for failure: ProviderFailure) -> VoiceQualityFallbackPlan {
        switch failure {
        case .cancelled:
            return VoiceQualityFallbackPlan(engines: [], leavesProviderReady: true)
        case .unauthorized, .rateLimited, .creditsUsedUp, .badVoice:
            return VoiceQualityFallbackPlan(engines: SyntheticFallbackOrder.engines, leavesProviderReady: false)
        default:
            return VoiceQualityFallbackPlan(engines: SyntheticFallbackOrder.engines, leavesProviderReady: true)
        }
    }
}

/// Speaks with one quality preset through the provider HTTP seam. URLSession only, via `ProviderHTTPTransport`.
public struct VoiceQualitySpeaker: Sendable {
    public var meter: VoiceQualityMeter
    public var transport: any ProviderHTTPTransport
    public var log: ProviderLog

    public init(meter: VoiceQualityMeter, transport: any ProviderHTTPTransport, log: ProviderLog = ProviderLog()) {
        self.meter = meter
        self.transport = transport
        self.log = log
    }

    public func synthesize(text: String, preset: VoiceQualityPreset, voiceID: String?, credential: ProviderCredential) -> Synthesis {
        let meter = self.meter
        let transport = self.transport
        let log = self.log
        let voice = voiceID ?? preset.defaultVoiceID
        return Self.stream {
            let request = try VoiceQualityRequestBuilder.make(text: text, preset: preset, voiceID: voice, credential: credential)
            let spokenCount = VoiceQualityMarkup.spoken(text).count
            try meter.reserve(providerID: preset.providerID, characters: spokenCount)
            let response = try await transport.send(request)
            let key = credential.value(ProviderCredentialLocation.account) ?? ""
            log.record(
                "voice-quality \(VoiceQualityCall(request: request).description) status=\(response.status)",
                secrets: [key]
            )
            guard (200...299).contains(response.status) else {
                throw ProviderFailure.fromHTTPStatus(response.status)
            }
            let audio = try Self.audio(from: response.body, preset: preset)
            guard !audio.isEmpty else { throw ProviderFailure.invalidResponse }
            return audio
        }
    }

    public func synthesizeIfEnabled(text: String, defaults: UserDefaults, credential: ProviderCredential) -> Synthesis {
        switch VoiceQualityOptIn.selection(defaults: defaults) {
        case .synthetic:
            return Self.stream { throw VoiceQualityError.providerOff }
        case .preset(let preset):
            return synthesize(text: text, preset: preset, voiceID: preset.defaultVoiceID, credential: credential)
        }
    }

    private static func stream(_ work: @escaping @Sendable () async throws -> Data) -> Synthesis {
        let task = SynthesisTask()
        let chunks = AsyncThrowingStream<AudioChunk, Error> { continuation in
            let job = Task {
                do {
                    try Task.checkCancellation()
                    let audio = try await work()
                    try Task.checkCancellation()
                    continuation.yield(AudioChunk(data: audio, index: 0, isLast: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: VoiceQualityError.publicError(error))
                }
            }
            task.cancel = {
                job.cancel()
                continuation.finish(throwing: ProviderFailure.cancelled)
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason { job.cancel() }
            }
        }
        return Synthesis(chunks: chunks, cancel: { task.cancel() })
    }

    private static func audio(from body: Data, preset: VoiceQualityPreset) throws -> Data {
        switch preset {
        case .elevenLabsFast, .elevenLabsStudio:
            return body
        case .googleNeural2, .googleWavenet, .googleChirpHD:
            guard let json = ProviderJSON.object(body),
                  let encoded = json["audioContent"] as? String,
                  let audio = Data(base64Encoded: encoded) else { throw ProviderFailure.invalidResponse }
            return audio
        }
    }
}

/// A `TTSProvider` for one preset. It is not registered, so the card and the default stay on the local voice.
public struct VoiceQualityTTSAdapter: TTSProvider {
    public var preset: VoiceQualityPreset
    public var meter: VoiceQualityMeter
    public var log: ProviderLog

    public init(preset: VoiceQualityPreset, meter: VoiceQualityMeter, log: ProviderLog = ProviderLog()) {
        self.preset = preset
        self.meter = meter
        self.log = log
    }

    public var descriptor: ProviderDescriptor {
        preset.providerID == GoogleCloudTTSAdapter.id ? GoogleCloudTTSAdapter.descriptor : ElevenLabsTTSAdapter.descriptor
    }

    public func listVoices(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws -> [ProviderVoice] {
        _ = transport
        guard credential.value(ProviderCredentialLocation.account) != nil else {
            throw ProviderFailure.missingCredential
        }
        let list = preset.providerID == GoogleCloudTTSAdapter.id ? VoiceQualityAllowList.google : VoiceQualityAllowList.elevenLabs
        return list.map { ProviderVoice(id: $0.id, name: $0.name, language: preset.providerID == GoogleCloudTTSAdapter.id ? "en-US" : nil) }
    }

    public func synthesize(text: String, voice: ProviderVoice, credential: ProviderCredential, using transport: any ProviderHTTPTransport) -> Synthesis? {
        VoiceQualitySpeaker(meter: meter, transport: transport, log: log)
            .synthesize(text: text, preset: preset, voiceID: voice.id, credential: credential)
    }

    public func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws {
        if preset.providerID == GoogleCloudTTSAdapter.id {
            try await GoogleCloudTTSAdapter().validate(credential: credential, using: transport)
        } else {
            try await ElevenLabsTTSAdapter().validate(credential: credential, using: transport)
        }
    }
}
