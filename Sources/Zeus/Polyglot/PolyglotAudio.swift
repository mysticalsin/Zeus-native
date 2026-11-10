import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// 16 kHz mono samples from one input, plus a 0...1 level for the waveform.
struct PolyglotChunk: Sendable {
    var samples: [Float]
    var level: Double
}

enum PolyglotAudioError: LocalizedError {
    case microphoneDenied
    case screenRecordingDenied
    case noDisplay
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is off. Turn it on in System Settings, Privacy and Security."
        case .screenRecordingDenied: "Mac audio needs Screen & System Audio Recording. Turn Zeus on in System Settings, Privacy and Security."
        case .noDisplay: "No display to listen through."
        case .engine(let message): message
        }
    }
}

/// The microphone through AVAudioEngine, converted to 16 kHz mono.
final class PolyglotMicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var resampler: AudioSamples.Resampler?
    private var running = false
    private var observer: NSObjectProtocol?
    /// The input changed or went away while running (a headset unplugged): the engine has stopped on its own.
    var onStopped: (@Sendable (String) -> Void)?

    func start(onChunk: @escaping @Sendable (PolyglotChunk) -> Void) async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw PolyglotAudioError.microphoneDenied }
        default: throw PolyglotAudioError.microphoneDenied
        }
        // Stop was pressed while the permission sheet was up: the microphone never turns on.
        try Task.checkCancellation()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw PolyglotAudioError.engine("The microphone has no input.") }
        let resampler = AudioSamples.Resampler(from: format)
        self.resampler = resampler
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = resampler.convert(buffer)
            guard !samples.isEmpty else { return }
            onChunk(PolyglotChunk(samples: samples, level: Self.level(samples)))
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw PolyglotAudioError.engine("The microphone didn't start: \(error.localizedDescription)")
        }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.onStopped?("The microphone changed or was unplugged, so captions stopped. Press play to start again.")
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    static func level(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        return min(Double(rms) * 8, 1)
    }
}

/// What the Mac is playing, through ScreenCaptureKit's audio capture. It asks for Screen & System
/// Audio Recording the first time this mode starts, never before. Zeus's own sound is left out.
final class PolyglotSystemCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var resampler: AudioSamples.Resampler?
    private var resamplerRate = 0.0
    private var onChunk: (@Sendable (PolyglotChunk) -> Void)?
    var onStopped: (@Sendable (String) -> Void)?
    private let queue = DispatchQueue(label: "zeus.polyglot.system-audio")

    func start(onChunk: @escaping @Sendable (PolyglotChunk) -> Void) async throws {
        // Asks once, and only now: the person chose Mac audio.
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw PolyglotAudioError.screenRecordingDenied
        }
        // Stop was pressed while the permission sheet was up: nothing starts.
        try Task.checkCancellation()
        guard let display = content.displays.first else { throw PolyglotAudioError.noDisplay }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // Audio only matters; keep the (required) picture as small and slow as possible.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.onChunk = onChunk
        do { try await stream.startCapture() } catch {
            self.onChunk = nil
            throw PolyglotAudioError.screenRecordingDenied
        }
        self.stream = stream
    }

    func stop() {
        let stream = stream
        self.stream = nil
        onChunk = nil
        resampler = nil
        if let stream { Task { try? await stream.stopCapture() } }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let onChunk, let buffer = Self.buffer(from: sampleBuffer) else { return }
        if resampler == nil || resamplerRate != buffer.format.sampleRate {
            resampler = AudioSamples.Resampler(from: buffer.format)
            resamplerRate = buffer.format.sampleRate
        }
        guard let samples = resampler?.convert(buffer), !samples.isEmpty else { return }
        onChunk(PolyglotChunk(samples: samples, level: PolyglotMicCapture.level(samples)))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        self.stream = nil
        onStopped?("Mac audio stopped: \(error.localizedDescription)")
    }

    private static func buffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        var copy = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &copy) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
