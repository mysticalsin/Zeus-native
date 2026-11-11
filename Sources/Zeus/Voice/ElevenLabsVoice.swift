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
    /// A stock ElevenLabs voice, used until a voice ID is saved.
    static let defaultVoiceID = "JBFqnCBsd6RMkjVDRZzb"
    /// Offline fallback when ElevenLabs is unavailable (matches the Obsidian orb preset).
    static let offlineKokoroVoice = "am_michael"
    static let offlineKokoroSpeed = 0.94

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
    static func voiceSettings(for personality: ZeusPersonality) -> [String: Any] {
        switch personality {
        case .plain: ["stability": 0.45, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": true]
        case .ultron: ["stability": 0.35, "similarity_boost": 0.8, "style": 0.3, "use_speaker_boost": true, "speed": 0.95]
        }
    }

    /// The JSON body of a direct text to speech request.
    static func speechBody(text: String, personality: ZeusPersonality) -> [String: Any] {
        ["text": text, "model_id": model, "voice_settings": voiceSettings(for: personality)]
    }

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

    func request(for text: String) -> URLRequest {
        switch route {
        case .direct(let apiKey):
            let voice = Self.savedVoiceID() ?? voiceID ?? Self.defaultVoiceID
            var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream")!
            components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000"),
                                     URLQueryItem(name: "optimize_streaming_latency", value: "3")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
            request.httpBody = try? JSONSerialization.data(withJSONObject: Self.speechBody(text: text, personality: .current()))
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


/// Plays 16-bit little-endian mono PCM chunks as they stream in.
@MainActor
final class StreamingPCMPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var pending = 0
    private var carry: UInt8?
    private var started = false
    private var sampleOffset: Double = 0

    init(sampleRate: Double = 24_000) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    var isPlaying: Bool { pending > 0 }

    func enqueue(_ data: Data) {
        var bytes = data
        if let carry { bytes.insert(carry, at: 0); self.carry = nil }
        if bytes.count % 2 == 1 { carry = bytes.removeLast() }
        let frames = bytes.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        bytes.withUnsafeBytes { raw in
            for index in 0..<frames {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                out[index] = Float(sample) / 32_768
            }
        }
        if UltronVoiceEffect.enabled, let channel = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            var samples = (0..<count).map { channel[$0] }
            samples = UltronVoiceEffect.process(samples, sampleRate: format.sampleRate, sampleOffset: sampleOffset)
            for index in 0..<count { channel[index] = samples[index] }
        }
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        sampleOffset += Double(frames)
        pending += 1
        node.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in if let self { self.pending = max(0, self.pending - 1) } }
        }
        if !node.isPlaying { node.play() }
    }

    func drained() async {
        while pending > 0, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(40)) }
    }

    func stop() {
        node.stop()
        pending = 0
        carry = nil
        sampleOffset = 0
    }
}
