import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed failures for the quality-preset path. Descriptions name the failure only.
/// A key, a response body, and a URL are never part of the text.
public enum VoiceQualityError: Error, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case voiceRefused
    case providerOff
    case meterExceeded
    case meterCorrupt
    case missingCredential
    case keyRejected
    case requestTooLarge
    case endpointRefused

    public var description: String {
        switch self {
        case .voiceRefused: "voice refused"
        case .providerOff: "provider is off"
        case .meterExceeded: "character meter exceeded"
        case .meterCorrupt: "character meter unreadable"
        case .missingCredential: "missing credential"
        case .keyRejected: VoiceQualityKeyGate.rejectedMessage
        case .requestTooLarge: "The request is too long."
        case .endpointRefused: "The voice endpoint is not allowed."
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

/// A key is trimmed, then refused when a control or format character remains or its UTF-8 form is longer than 256 bytes.
/// The message is fixed. A longer key is never stored, logged, or placed in a header, so redaction stays bounded.
/// Newline, carriage return, tab, and NUL cannot reach a header or the meter.
public enum VoiceQualityKeyGate {
    public static let rejectedMessage = "The key is not valid."
    public static let maxLength = 256

    public static func accepted(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{000B}\u{000C}"))
        guard VoiceProviderKeyPolicy.accepts(trimmed) else { return nil }
        return trimmed
    }
}

/// One speak request stays at or under 5,000 UTF-8 bytes. The 50,000 figure is the cumulative meter, also in UTF-8 bytes.
/// ElevenLabs and Google bill by their own character counts. Bytes are the cap so combining marks cannot slip past it.
public enum VoiceQualityRequestSize {
    public static let limit = 5_000

    public static func allows(_ characters: Int) -> Bool {
        characters >= 0 && characters <= limit
    }
}

/// Quality requests may only use the two provider hosts, over HTTPS, with no userinfo.
public enum VoiceQualityEndpoint {
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return false }
        switch url.host?.lowercased() {
        case "api.elevenlabs.io", "texttospeech.googleapis.com": return true
        default: return false
        }
    }
}

/// A redirect would replay `xi-api-key` or `X-Goog-Api-Key`. The task delegate returns nil.
public enum VoiceQualityRedirect {
    public static func forwarded(_ proposed: URLRequest, from original: URL?) -> URLRequest? {
        _ = proposed
        _ = original
        return nil
    }
}

final class VoiceQualityRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(VoiceQualityRedirect.forwarded(request, from: task.originalRequest?.url ?? response.url))
    }
}

/// The session the quality speaker uses when the caller does not inject a test transport.
/// Redirects are refused by `VoiceQualityRedirectDelegate`.
final class VoiceQualityURLSessionTransport: ProviderHTTPTransport, @unchecked Sendable {
    let delegate = VoiceQualityRedirectDelegate()
    let timeout: TimeInterval
    let log: ProviderLog
    let protocolClasses: [AnyClass]

    init(timeout: TimeInterval = ProviderHTTPBudget.requestTimeout, log: ProviderLog = ProviderLog(), protocolClasses: [AnyClass] = []) {
        self.timeout = timeout
        self.log = log
        self.protocolClasses = protocolClasses
    }

    func send(_ request: ProviderHTTPRequest) async throws -> ProviderHTTPResponse {
        let urlRequest = try request.urlRequest(timeout: timeout)
        let session = URLSession(configuration: configuration(), delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ProviderFailure.invalidResponse }
        guard !(300...399).contains(http.statusCode) else { throw VoiceQualityError.endpointRefused }
        log.record("voice-quality \(request.method) \(request.url.host ?? "-") status=\(http.statusCode)")
        return ProviderHTTPResponse(status: http.statusCode, body: data)
    }

    func stream(_ request: ProviderHTTPRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let interval = self.timeout
        let response = Result { try request.urlRequest(timeout: interval) }
        let delegate = self.delegate
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try response.get()
                    let session = URLSession(configuration: self.configuration(), delegate: delegate, delegateQueue: nil)
                    defer { session.finishTasksAndInvalidate() }
                    let (data, httpResponse) = try await session.data(for: urlRequest)
                    guard let http = httpResponse as? HTTPURLResponse else { throw ProviderFailure.invalidResponse }
                    guard !(300...399).contains(http.statusCode) else { throw VoiceQualityError.endpointRefused }
                    continuation.yield(.status(http.statusCode))
                    if !data.isEmpty { continuation.yield(.chunk(data)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ProviderFailure.wrap(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        return configuration
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

    public var title: String {
        switch self {
        case .elevenLabsFast: "ElevenLabs Fast"
        case .elevenLabsStudio: "ElevenLabs Studio"
        case .googleNeural2: "Google Neural2"
        case .googleWavenet: "Google WaveNet"
        case .googleChirpHD: "Google Chirp HD"
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

/// The provider the user picked. Automatic never selects a cloud preset.
public enum VoiceQualitySpeakChoice: String, Sendable, Equatable {
    case automatic
    case elevenLabs
    case googleCloud
}

/// Which cloud keys exist. A key alone does not select a provider.
public struct VoiceQualitySpeakKeys: Equatable, Sendable {
    public var elevenLabs: Bool
    public var openAI: Bool
    public var gemini: Bool
    public var googleCloud: Bool
    public var kokoroReady: Bool

    public init(elevenLabs: Bool = false, openAI: Bool = false, gemini: Bool = false, googleCloud: Bool = false, kokoroReady: Bool = false) {
        self.elevenLabs = elevenLabs
        self.openAI = openAI
        self.gemini = gemini
        self.googleCloud = googleCloud
        self.kokoroReady = kokoroReady
    }
}

/// Cloud presets run only when this gate says the user selected that provider and a key exists.
/// Automatic stays `zeus.synthetic`.
public enum VoiceQualityRoute {
    public static func selection(choice: VoiceQualitySpeakChoice, keys: VoiceQualitySpeakKeys, preset: VoiceQualityPreset?, providerFailed: Bool = false) -> VoiceQualitySelection {
        guard let preset, !providerFailed else { return .synthetic }
        switch choice {
        case .elevenLabs where preset.providerID == ElevenLabsTTSAdapter.id && keys.elevenLabs:
            return .preset(preset)
        case .googleCloud where preset.providerID == GoogleCloudTTSAdapter.id && keys.googleCloud:
            return .preset(preset)
        case .automatic, .elevenLabs, .googleCloud:
            return .synthetic
        }
    }

    public static func activeVoiceID(choice: VoiceQualitySpeakChoice, keys: VoiceQualitySpeakKeys, preset: VoiceQualityPreset?, providerFailed: Bool = false) -> String {
        switch selection(choice: choice, keys: keys, preset: preset, providerFailed: providerFailed) {
        case .synthetic: VoiceSpeakAllowlist.syntheticID
        case .preset(let chosen): chosen.defaultVoiceID
        }
    }
}

public enum VoiceQualitySelection: Equatable, Sendable {
    case synthetic
    case preset(VoiceQualityPreset)
}

/// Providers stay off unless the user explicitly chose a preset.
/// A migrated or legacy `voice.ttsProvider` value is not consent. The default is `zeus.synthetic`.
public enum VoiceQualityOptIn {
    public static let presetKey = "voice.quality.preset"
    public static let consentKey = "voice.quality.consent"

    /// Writes the explicit choice. `nil` clears it and leaves the voice on `zeus.synthetic`.
    public static func set(_ preset: VoiceQualityPreset?, defaults: UserDefaults) {
        if let preset {
            defaults.set(true, forKey: consentKey)
            defaults.set(preset.rawValue, forKey: presetKey)
            defaults.set(providerRaw(for: preset.providerID), forKey: VoiceProviderPreferences.selectionKey)
        } else {
            defaults.set(false, forKey: consentKey)
            defaults.removeObject(forKey: presetKey)
        }
    }

    /// The one settings picker. Local, a mismatched preset, or a missing preset clears the opt-in.
    public static func applyPicker(providerID: String, preset: VoiceQualityPreset?, defaults: UserDefaults) {
        guard providerID != VoiceProviderChoice.localID,
              let preset,
              preset.providerID == providerID else {
            set(nil, defaults: defaults)
            return
        }
        set(preset, defaults: defaults)
    }

    public static func selection(defaults: UserDefaults) -> VoiceQualitySelection {
        guard defaults.bool(forKey: consentKey),
              let raw = defaults.string(forKey: VoiceProviderPreferences.selectionKey),
              let id = explicitProviderID(raw),
              let presetRaw = defaults.string(forKey: presetKey),
              let preset = VoiceQualityPreset(rawValue: presetRaw),
              preset.providerID == id else { return .synthetic }
        return .preset(preset)
    }

    private static func explicitProviderID(_ raw: String) -> String? {
        switch raw {
        case VoiceTTSProvider.elevenLabs.rawValue: ElevenLabsTTSAdapter.id
        case VoiceTTSProvider.googleCloud.rawValue: GoogleCloudTTSAdapter.id
        default: nil
        }
    }

    private static func providerRaw(for providerID: String) -> String {
        providerID == GoogleCloudTTSAdapter.id ? VoiceTTSProvider.googleCloud.rawValue : VoiceTTSProvider.elevenLabs.rawValue
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
        guard let key = VoiceQualityKeyGate.accepted(credential.fields[ProviderCredentialLocation.account] ?? "") else {
            throw VoiceQualityError.keyRejected
        }
        guard VoiceQualityRequestSize.allows(VoiceQualityMarkup.spoken(text).utf8.count) else {
            throw VoiceQualityError.requestTooLarge
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

    public init(meter: VoiceQualityMeter, transport: (any ProviderHTTPTransport)? = nil, log: ProviderLog = ProviderLog()) {
        self.meter = meter
        self.transport = transport ?? VoiceQualityURLSessionTransport(log: log)
        self.log = log
    }

    /// A call that did not come through `VoiceQualityRoute` or `synthesizeIfEnabled`. It does not read the key or open a request.
    func synthesize(text: String, preset: VoiceQualityPreset, voiceID: String?, credential: ProviderCredential) -> Synthesis {
        _ = (text, preset, voiceID, credential)
        return Self.refused()
    }

    public func synthesize(text: String, choice: VoiceQualitySpeakChoice, keys: VoiceQualitySpeakKeys, preset: VoiceQualityPreset?, credential: ProviderCredential, providerFailed: Bool = false, voiceID: String? = nil) -> Synthesis {
        switch VoiceQualityRoute.selection(choice: choice, keys: keys, preset: preset, providerFailed: providerFailed) {
        case .synthetic:
            return Self.refused()
        case .preset(let chosen):
            return synthesizeApproved(text: text, preset: chosen, voiceID: voiceID ?? chosen.defaultVoiceID, credential: credential)
        }
    }

    func synthesizeApproved(text: String, preset: VoiceQualityPreset, voiceID: String?, credential: ProviderCredential) -> Synthesis {
        let meter = self.meter
        let transport = self.transport
        let log = self.log
        let voice = voiceID ?? preset.defaultVoiceID
        return Self.stream {
            guard let key = VoiceQualityKeyGate.accepted(credential.fields[ProviderCredentialLocation.account] ?? "") else {
                throw VoiceQualityError.keyRejected
            }
            let spoken = VoiceQualityMarkup.spoken(text)
            let bytes = spoken.utf8.count
            guard VoiceQualityRequestSize.allows(bytes) else { throw VoiceQualityError.requestTooLarge }
            let clean = ProviderCredential(fields: [ProviderCredentialLocation.account: key])
            let request = try VoiceQualityRequestBuilder.make(text: text, preset: preset, voiceID: voice, credential: clean)
            guard VoiceQualityEndpoint.allows(request.url) else { throw VoiceQualityError.endpointRefused }
            try meter.reserve(providerID: preset.providerID, characters: bytes)
            let response = try await transport.send(request)
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

    static func refused() -> Synthesis {
        stream { throw VoiceQualityError.providerOff }
    }

    public func synthesizeIfEnabled(text: String, defaults: UserDefaults, credential: ProviderCredential) -> Synthesis {
        guard case .preset(let preset) = VoiceQualityOptIn.selection(defaults: defaults) else {
            return Self.refused()
        }
        let choice: VoiceQualitySpeakChoice = preset.providerID == GoogleCloudTTSAdapter.id ? .googleCloud : .elevenLabs
        guard VoiceQualityKeyGate.accepted(credential.fields[ProviderCredentialLocation.account] ?? "") != nil else {
            return Self.refused()
        }
        var keys = VoiceQualitySpeakKeys()
        if choice == .elevenLabs { keys.elevenLabs = true }
        if choice == .googleCloud { keys.googleCloud = true }
        return synthesize(text: text, choice: choice, keys: keys, preset: preset, credential: credential)
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
        _ = (text, voice, credential, transport, meter, preset, log)
        return VoiceQualitySpeaker.refused()
    }

    public func validate(credential: ProviderCredential, using transport: any ProviderHTTPTransport) async throws {
        if preset.providerID == GoogleCloudTTSAdapter.id {
            try await GoogleCloudTTSAdapter().validate(credential: credential, using: transport)
        } else {
            try await ElevenLabsTTSAdapter().validate(credential: credential, using: transport)
        }
    }
}
