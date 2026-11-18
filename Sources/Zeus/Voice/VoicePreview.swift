import AVFoundation
import Foundation
import Observation
import ZeusCore

/// Per-voice preview in Settings > Voice. One original sentence is rendered with the owner's own key, played
/// from a temporary file, and the file is deleted when playback ends. Nothing is bundled or kept.
@MainActor
@Observable
final class VoicePreviewModel {
    static let shared = VoicePreviewModel()

    /// `provider.rawValue:voice` of the preview that is loading or playing.
    private(set) var activeID: String?
    private(set) var loading = false
    var message: String?

    private var player: AVAudioPlayer?
    private var playerDelegate: PreviewDelegate?
    private var playingFile: URL?
    private var task: Task<Void, Never>?

    static func id(_ provider: VoiceTTSProvider, _ voice: String) -> String { "\(provider.rawValue):\(voice)" }

    func isActive(_ provider: VoiceTTSProvider, _ voice: String) -> Bool { activeID == Self.id(provider, voice) }

    func toggle(_ provider: VoiceTTSProvider, voice: String, now: Date = Date()) {
        let id = Self.id(provider, voice)
        let wasActive = activeID == id
        stop()
        if wasActive { return }
        if provider == .openAICompatible, OpenAITTSVoice.isRetired(now: now) {
            message = OpenAISpeechRetirement.endedNote
            return
        }
        let env = ProcessInfo.processInfo.environment
        let audibleOK = (env["AUDIBLE-OK"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if env["ZEUS_SILENT_TESTS"] == "1" || audibleOK == "0" || audibleOK == "false" {
            message = "Silent mode is on. The preview was not played."
            return
        }
        activeID = id
        loading = true
        message = nil
        task = Task { [weak self] in
            let url = await Self.render(provider, voice: voice)
            guard let self, self.activeID == id, !Task.isCancelled else {
                if let url { try? FileManager.default.removeItem(at: url) }
                return
            }
            self.loading = false
            guard let url else {
                self.activeID = nil
                self.message = "Couldn't make the preview. Check the key and your connection."
                VoiceLog.log("voice", "preview engine=\(provider.rawValue) voice=\(voice) ok=false")
                return
            }
            self.play(url, id: id)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        playerDelegate = nil
        if let file = playingFile { try? FileManager.default.removeItem(at: file) }
        playingFile = nil
        activeID = nil
        loading = false
    }

    private func play(_ url: URL, id: String) {
        playingFile = url
        guard let item = try? AVAudioPlayer(contentsOf: url) else {
            message = "Couldn't play the preview."
            stop()
            return
        }
        let delegate = PreviewDelegate { [weak self] in Task { @MainActor in if self?.activeID == id { self?.stop() } } }
        item.delegate = delegate
        player = item
        playerDelegate = delegate
        if !item.play() {
            message = "Couldn't play the preview."
            stop()
        }
    }

    /// A temporary WAV for the sentence in `voice`, or nil. Uses the saved key, never a bundled clip.
    private static func render(_ provider: VoiceTTSProvider, voice: String) async -> URL? {
        let sentence = VoiceCatalogPreview.sentence
        switch provider {
        case .openAICompatible:
            guard var config = OpenAITTSVoice.config(), config.responseFormat == "wav" else { return nil }
            config.voice = voice
            guard let request = OpenAITTSRequest.makeRequest(text: sentence, config: config) else { return nil }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else { return nil }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-preview-\(UUID().uuidString).wav")
                try data.write(to: url)
                return url
            } catch { return nil }
        case .gemini:
            guard let pcm = await GeminiTTSVoice.renderPCM(sentence, voice: voice) else { return nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zeus-preview-\(UUID().uuidString).wav")
            do {
                try GeminiTTSRequest.wav(fromPCM: pcm).write(to: url)
                return url
            } catch { return nil }
        default:
            return nil
        }
    }
}

private final class PreviewDelegate: NSObject, AVAudioPlayerDelegate {
    private let finished: () -> Void
    init(finished: @escaping () -> Void) { self.finished = finished }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finished() }
}
