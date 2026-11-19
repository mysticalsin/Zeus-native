import AVFoundation
import Foundation

/// Renders a synthesized file through the Ultron chain to a new WAV (silent Settings preview, QA).
/// Live playback goes through `UltronAudioChain`.
enum VoiceWAVPlayback {
    static func writeProcessedCopy(from source: URL, to destination: URL) throws {
        try UltronOfflineRender.writeProcessedCopy(from: source, to: destination, parameters: UltronVoiceEffect.parameters)
    }
}
