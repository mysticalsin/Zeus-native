import AVFoundation
import Foundation

/// Feeds a WAV through `WakeWordListener` at real-time pace (no microphone). Shared by
/// `--voice-selftest` and `zeus debug dictate-file` when the clip is a wake phrase.
enum WakeWordFilePlayer {
    /// Returns the request spoken after the wake phrase, or nil when nothing matched.
    static func play(url: URL, localeIdentifier: String, onWake: @escaping @Sendable (String) -> Void) async -> String? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let rate = file.processingFormat.sampleRate
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let listener = WakeWordListener(localeIdentifier: localeIdentifier)
        guard listener.onDeviceSupported else { return nil }
        let box = WakeBox()
        listener.onWake = { request in
            box.set(request)
            onWake(request)
        }
        let step = 4096
        var index = 0
        let total = samples.count + Int(rate * 3)
        while index < total, box.value == nil {
            let count = min(step, total - index)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let target = chunk.floatChannelData else { break }
            chunk.frameLength = AVAudioFrameCount(count)
            for channelIndex in 0..<Int(file.processingFormat.channelCount) {
                for i in 0..<count {
                    target[channelIndex][i] = index + i < samples.count ? samples[index + i] : 0
                }
            }
            listener.feed(chunk)
            index += count
            try? await Task.sleep(for: .seconds(Double(count) / rate))
        }
        var waited = 0
        while box.value == nil, waited < 40 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        listener.stop()
        return box.value
    }

    private final class WakeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var value: String? { lock.withLock { stored } }
        func set(_ text: String) { lock.withLock { stored = text } }
    }
}
