import AVFoundation
import Foundation

/// Plays a WAV file with the Ultron post chain applied offline to samples (K3).
@MainActor
enum VoiceWAVPlayback {
    static func play(url: URL) async {
        let processed = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-ultron-\(UUID().uuidString).wav")
        do {
            try writeProcessedCopy(from: url, to: processed)
        } catch {
            return
        }
        defer { try? FileManager.default.removeItem(at: processed) }
        guard let player = try? AVAudioPlayer(contentsOf: processed) else { return }
        player.play()
        while player.isPlaying, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(40)) }
    }

    /// Renders processed audio to a new WAV path (Settings test button, silent QA).
    static func writeProcessedCopy(from source: URL, to destination: URL) throws {
        guard let file = try? AVAudioFile(forReading: source) else { throw CocoaError(.fileReadUnknown) }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CocoaError(.fileReadUnknown)
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw CocoaError(.fileReadUnknown) }
        let count = Int(buffer.frameLength)
        for channelIndex in 0..<Int(format.channelCount) {
            let channel = channels[channelIndex]
            let samples = UltronVoiceEffect.process(Array(UnsafeBufferPointer(start: channel, count: count)),
                                                   sampleRate: format.sampleRate)
            for index in 0..<count { channel[index] = samples[index] }
        }
        let out = try AVAudioFile(forWriting: destination, settings: format.settings)
        try out.write(from: buffer)
    }
}
