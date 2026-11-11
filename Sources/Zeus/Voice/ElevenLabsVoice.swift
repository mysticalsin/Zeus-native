import AVFoundation
import Foundation
import Security
import ZeusCore

/// ElevenLabs streaming text to speech. A key on this Mac (Keychain `com.zeus.app`, account
/// `elevenlabs.api-key`, migrated from `com.zeus.elevenlabs`) calls ElevenLabs directly; otherwise
/// the ZEUS worker's secret is used through `/tts`. Keys are never logged or shown.
struct ElevenLabsVoice: Sendable {
    static let service = "com.zeus.app"
    static let model = "eleven_flash_v2_5"
    /// A stock ElevenLabs voice, used until the designed Ultron voice id is saved.
    static let defaultVoiceID = "JBFqnCBsd6RMkjVDRZzb"
    /// Offline fallback when ElevenLabs is unavailable (matches the Obsidian orb preset).
    static let offlineKokoroVoice = UltronCloudVoice.kokoroVoice
    static let offlineKokoroSpeed = UltronCloudVoice.kokoroSpeed

    /// Where the ElevenLabs key lives. Tony's setup keeps it as the worker secret
    /// `ELEVENLABS_API_KEY`, so with no key on this Mac ZEUS streams through the worker's `/tts`
    /// (same PCM format) using `worker.url` and `worker.token` from the Keychain. Nobody is asked
    /// to type a key that already exists.
    enum Route: Sendable {
        case direct(apiKey: String)
        case worker(url: URL, token: String)
    }

    let route: Route
    let voiceID: String?

    var description: String {
        switch route {
        case .direct: "ElevenLabs voice (\(Self.model), streaming, system voice as fallback)"
        case .worker: "ElevenLabs voice via your Zeus worker (streaming, system voice as fallback)"
        }
    }

    /// Delivery for each personality (docs/PERSONA.md, section 6). Plain is a natural, steady read.
    /// Ultron is more expressive: lower stability for range, some style exaggeration (supported by
    /// the flash model, at a small latency cost), speaker boost on, and a touch unhurried.
    static func voiceSettings(for personality: ZeusPersonality, model: String = ElevenLabsVoice.model) -> [String: Any] {
        // Studio (UNVERIFIED model, see `ElevenLabsQuality.studioModel`): only the settings every model takes.
        if model == ElevenLabsQuality.studioModel {
            return ["stability": 0.5, "similarity_boost": 0.8, "use_speaker_boost": true]
        }
        switch personality {
        case .plain: ["stability": 0.45, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": true]
        case .ultron:
            UltronCloudVoice.elevenLabsSettings.reduce(into: ["use_speaker_boost": true] as [String: Any]) { $0[$1.key] = $1.value }
        }
    }

    /// The JSON body of a direct text to speech request.
    static func speechBody(text: String, personality: ZeusPersonality, model: String = ElevenLabsVoice.model) -> [String: Any] {
        ["text": text, "model_id": model, "voice_settings": voiceSettings(for: personality, model: model)]
    }

    /// 24 kHz 16-bit mono PCM, played without decoding. `pcm_44100` needs the Pro tier (ElevenLabs docs);
    /// the tier rules for `pcm_32000` and `pcm_48000` are not stated there, so they are not used.
    static let pcmOutputFormat = "pcm_24000"

    static func isKeyRejection(_ status: Int) -> Bool { status == 401 || status == 402 || status == 429 }

    static func detailStatus(from body: Data) -> String {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let detail = json?["detail"] as? [String: Any]
        return (detail?["status"] as? String) ?? "unknown"
    }

    /// One line for voice.log: HTTP status and ElevenLabs detail.status only (never the key).
    static func logKeyRejection(status: Int, body: Data) {
        VoiceLog.log("elevenlabs", "HTTP \(status) detail.status=\(detailStatus(from: body))")
    }

    static func settingsMessage(status: Int, body: Data) -> String {
        if status == 429 {
            let detail = detailStatus(from: body)
            if detail != "unknown" {
                return "ElevenLabs rate limit (\(detail)), using the offline voice"
            }
            return "ElevenLabs rate limit hit, using the offline voice"
        }
        _ = body
        return "ElevenLabs key rejected, using the offline voice"
    }

    /// The voice picked or designed in Settings, read on each request so a new choice applies to the
    /// next sentence without restarting. Nil when none was saved.
    static func savedVoiceID() -> String? {
        let saved = Keychain.get("elevenlabs.voice-id")?.filter { $0.isLetter || $0.isNumber }
        return saved?.isEmpty == false ? saved : nil
    }

    var engineName: String {
        if case .direct = route { return "elevenlabs-direct" }
        return "elevenlabs-worker"
    }

    /// The first route ZEUS tries.
    static func load() -> ElevenLabsVoice? { loadRoutes().first }

    /// True when a key or a worker route exists. Cheap enough to ask before every reply.
    static var hasRoute: Bool { !loadRoutes().isEmpty }

    /// Every ElevenLabs route on this Mac, in order: the key in the Keychain straight from the Mac
    /// (no worker needed), then the ZEUS worker `/tts`. The system voice comes after both.
    static func loadRoutes() -> [ElevenLabsVoice] {
        let voice = savedVoiceID()
        var routes: [ElevenLabsVoice] = []
        if let key = Keychain.get("elevenlabs.api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            routes.append(ElevenLabsVoice(route: .direct(apiKey: key), voiceID: voice ?? defaultVoiceID))
        }
        if let worker = loadWorker(voice: voice) { routes.append(worker) }
        return routes
    }

    private static func loadWorker(voice: String?) -> ElevenLabsVoice? {
        if let raw = Keychain.get("worker.url"), let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "https", let token = Keychain.get("worker.token"), !token.isEmpty {
            // The worker's own ELEVENLABS_VOICE_ID applies unless a voice was picked here.
            return ElevenLabsVoice(route: .worker(url: url, token: token), voiceID: voice)
        }
        return nil
    }

    func request(for text: String, model: String = ElevenLabsVoice.model) -> URLRequest {
        switch route {
        case .direct(let apiKey):
            let voice = Self.savedVoiceID() ?? voiceID ?? Self.defaultVoiceID
            var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream")!
            components.queryItems = [URLQueryItem(name: "output_format", value: Self.pcmOutputFormat),
                                     URLQueryItem(name: "optimize_streaming_latency", value: "3")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
            request.httpBody = try? JSONSerialization.data(withJSONObject: Self.speechBody(text: text, personality: .current(), model: model))
            return request
        case .worker(let url, let token):
            var request = URLRequest(url: url.appendingPathComponent("tts"))
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: String] = ["text": text, "provider": "elevenlabs"]
            if let voice = Self.savedVoiceID() ?? voiceID { body["voice"] = voice }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return request
        }
    }
}

