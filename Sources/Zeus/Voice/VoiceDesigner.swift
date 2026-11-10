import AVFoundation
import Foundation
import Observation
import ZeusCore

/// ElevenLabs Voice Design: Tony describes an original voice, ElevenLabs returns three previews,
/// he plays them and keeps one as his "Zeus" voice. Nothing is cloned and no real person is named.
///
/// API (elevenlabs.io/docs/api-reference/text-to-voice):
/// - `POST /v1/text-to-voice/design` with `voice_description`, `text` (100 to 1000 characters) and
///   `model_id` returns `previews` (`audio_base_64`, `generated_voice_id`, `media_type`,
///   `duration_secs`) and the `text` used. Previews cost the credits of the text, once.
/// - `POST /v1/text-to-voice` with `voice_name`, `voice_description` and `generated_voice_id`
///   saves the chosen preview as a voice (one voice slot) and returns its `voice_id`.
/// Designed voices work with every ElevenLabs text to speech model, so replies stay on the
/// low-latency flash model. Runs only when Tony clicks; the key is never logged or shown.
enum VoiceDesigner {
    static let base = URL(string: "https://api.elevenlabs.io")!
    /// The documented default design model (the other choice is `eleven_ttv_v3`).
    static let designModel = "eleven_multilingual_ttv_v2"
    static let voiceName = "Zeus"
    static let textRange = 100...1000

    /// Generic qualities only, following the ElevenLabs prompt guide: language first, then age,
    /// timbre, attitude, pacing and recording quality.
    static let voiceDescription = """
    American English, adult male in his forties. A deep, smooth, measured voice with a warm low \
    resonance and a slight synthetic sheen. Articulate and quietly amused, theatrical but calm. \
    Unhurried pacing with deliberate pauses before key words. Studio-quality recording.
    """

    /// An original line in the persona's manner, long enough for a stable preview.
    static let sampleText = """
    Good evening, Tony. I've been looking over your week, and I have to say, it's ambitious. \
    Eleven meetings, four deadlines, and one dentist appointment you've been avoiding with real \
    dedication. Don't worry. I've moved the pieces around. Evolution is mostly patience, and I \
    have plenty of it. Shall we begin?
    """

    struct Preview: Identifiable, Equatable, Sendable {
        let id: String
        let audio: Data
        let mediaType: String
        let duration: Double
    }

    enum Failure: Error, Equatable {
        case noKey, badKey, quota, rateLimited, voiceSlotsFull, network, rejected(String), server(Int), unreadable

        /// One plain line for the Settings page.
        var message: String {
            switch self {
            case .noKey: "Save your ElevenLabs key first."
            case .badKey: "ElevenLabs refused the key."
            case .quota: "Your ElevenLabs credits have run out for now."
            case .rateLimited: "ElevenLabs is busy. Try again in a minute."
            case .voiceSlotsFull: "Your ElevenLabs voice slots are full. Remove a voice there, then try again."
            case .network: "Could not reach ElevenLabs. Check the connection."
            case .rejected(let reason): "ElevenLabs rejected the request: \(reason)"
            case .server(let code): "ElevenLabs had a problem (\(code)). Try again later."
            case .unreadable: "ElevenLabs sent an answer Zeus could not read."
            }
        }
    }

    // MARK: Requests

    static func designRequest(apiKey: String, description: String = voiceDescription, text: String = sampleText) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent("v1/text-to-voice/design"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        let body: [String: Any] = ["voice_description": description, "text": text, "model_id": designModel]
        return post(components.url!, apiKey: apiKey, body: body, timeout: 90)
    }

    static func createRequest(apiKey: String, generatedVoiceID: String, description: String = voiceDescription,
                              playedNotSelected: [String] = []) -> URLRequest {
        var body: [String: Any] = ["voice_name": voiceName, "voice_description": description, "generated_voice_id": generatedVoiceID]
        if !playedNotSelected.isEmpty { body["played_not_selected_voice_ids"] = playedNotSelected }
        return post(base.appendingPathComponent("v1/text-to-voice"), apiKey: apiKey, body: body, timeout: 30)
    }

    private static func post(_ url: URL, apiKey: String, body: [String: Any], timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Responses

    static func parsePreviews(_ data: Data) throws -> [Preview] {
        struct Body: Decodable {
            struct Item: Decodable {
                let audio_base_64: String
                let generated_voice_id: String
                let media_type: String?
                let duration_secs: Double?
            }
            let previews: [Item]
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw Failure.unreadable }
        let previews = body.previews.compactMap { item -> Preview? in
            guard !item.generated_voice_id.isEmpty, let audio = Data(base64Encoded: item.audio_base_64), !audio.isEmpty else { return nil }
            return Preview(id: item.generated_voice_id, audio: audio, mediaType: item.media_type ?? "audio/mpeg", duration: item.duration_secs ?? 0)
        }
        if previews.isEmpty { throw Failure.unreadable }
        return previews
    }

    static func parseVoiceID(_ data: Data) throws -> String {
        struct Body: Decodable { let voice_id: String }
        guard let id = try? JSONDecoder().decode(Body.self, from: data).voice_id, !id.isEmpty else { throw Failure.unreadable }
        return id
    }

    /// Maps an error response to one plain failure. ElevenLabs errors carry `detail` as an object
    /// (`status`, `message`) or, for validation errors (422), a list of `{loc, msg, type}`.
    static func failure(status: Int, body: Data) -> Failure {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let detail = json?["detail"]
        let object = detail as? [String: Any]
        let code = ((object?["status"] as? String) ?? "").lowercased()
        let message = (object?["message"] as? String)
            ?? ((detail as? [[String: Any]])?.compactMap { $0["msg"] as? String }.first)
            ?? (detail as? String)
        if code.contains("quota") || code.contains("credit") { return .quota }
        if code.contains("voice_limit") || code.contains("voice_slots") { return .voiceSlotsFull }
        switch status {
        case 401, 403: return .badKey
        case 402: return .quota
        case 429: return .rateLimited
        case 400, 409, 422: return .rejected(message.map(short) ?? "please try again.")
        default: return .server(status)
        }
    }

    private static func short(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > 140 ? String(line.prefix(140)) + "…" : line
    }

    // MARK: Calls (only from a click in Settings)

    static func design(apiKey: String) async throws -> [Preview] {
        try parsePreviews(await send(designRequest(apiKey: apiKey)))
    }

    static func create(apiKey: String, generatedVoiceID: String, playedNotSelected: [String]) async throws -> String {
        try parseVoiceID(await send(createRequest(apiKey: apiKey, generatedVoiceID: generatedVoiceID, playedNotSelected: playedNotSelected)))
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw Failure.network }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw failure(status: status, body: data) }
        return data
    }
}

/// The Settings flow behind "Design Zeus's voice": design, play the previews, keep one.
@MainActor
@Observable
final class VoiceDesignModel {
    static let shared = VoiceDesignModel()

    enum Phase: Equatable {
        case idle, designing, ready, saving, saved, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var previews: [VoiceDesigner.Preview] = []
    private(set) var playingID: String?
    private var played: Set<String> = []
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playback: Task<Void, Never>?

    var busy: Bool { phase == .designing || phase == .saving }

    /// One short line under the button.
    var status: String {
        switch phase {
        case .idle: "Creates an original voice from a description: deep, measured, quietly amused. Uses ElevenLabs credits for one short sample."
        case .designing: "Designing three voices. This takes a few seconds."
        case .ready: "Play each one, then keep the voice you like."
        case .saving: "Saving the voice as \u{201C}\(VoiceDesigner.voiceName)\u{201D}."
        case .saved: "Saved. Zeus now speaks with this voice."
        case .failed(let message): message
        }
    }

    func design() {
        guard !busy else { return }
        guard let key = Self.apiKey() else { phase = .failed(VoiceDesigner.Failure.noKey.message); return }
        stop()
        previews = []
        played = []
        phase = .designing
        Task {
            do {
                previews = try await VoiceDesigner.design(apiKey: key)
                phase = .ready
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func togglePlay(_ preview: VoiceDesigner.Preview) {
        if playingID == preview.id { stop(); return }
        stop()
        guard let player = try? AVAudioPlayer(data: preview.audio) else {
            phase = .failed("That preview could not be played.")
            return
        }
        self.player = player
        played.insert(preview.id)
        playingID = preview.id
        player.play()
        playback = Task { [weak self] in
            while player.isPlaying, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(150)) }
            if let self, self.playingID == preview.id { self.playingID = nil }
        }
    }

    func use(_ preview: VoiceDesigner.Preview) {
        guard !busy else { return }
        guard let key = Self.apiKey() else { phase = .failed(VoiceDesigner.Failure.noKey.message); return }
        stop()
        phase = .saving
        let others = played.subtracting([preview.id]).sorted()
        Task {
            do {
                let voiceID = try await VoiceDesigner.create(apiKey: key, generatedVoiceID: preview.id, playedNotSelected: others)
                let settings = VoiceSettings.shared
                settings.setElevenVoice(voiceID)
                settings.engine = .elevenLabs
                previews = []
                phase = .saved
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    func stop() {
        playback?.cancel()
        playback = nil
        player?.stop()
        player = nil
        playingID = nil
    }

    private static func apiKey() -> String? {
        guard let key = Keychain.get("elevenlabs.api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    private static func message(for error: Error) -> String {
        (error as? VoiceDesigner.Failure ?? .network).message
    }
}
