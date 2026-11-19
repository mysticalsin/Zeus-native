import AVFoundation
import Foundation

/// Renders the macOS voice to buffers so it can run through the Ultron chain like every other engine.
/// The buffer callback arrives on a synthesizer thread, so it is set up here, outside any actor.
enum SystemVoiceRender {
    final class Box: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    /// `deliver` is called once per buffer; `finished` once, after the last (empty) buffer.
    nonisolated static func render(_ utterance: AVSpeechUtterance, with synthesizer: AVSpeechSynthesizer,
                                   deliver: @escaping @Sendable (Box) -> Void,
                                   finished: @escaping @Sendable () -> Void) {
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { finished() } else { deliver(Box(pcm)) }
        }
    }
}
