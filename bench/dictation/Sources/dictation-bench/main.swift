import AVFoundation
import FluidAudio
import Foundation
import Speech
import WhisperKit
import ZeusCore

// Usage: dictation-bench <clips dir> [parakeet|whisper|apple ...]
// Prints one Markdown table row per clip and a summary per engine.

struct Clip {
    let name: String
    let voice: String
    let reference: String
    let samples: [Float]
    var seconds: Double { Double(samples.count) / 16_000 }
}

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: source)
    if file.processingFormat == target { return Array(UnsafeBufferPointer(start: source.floatChannelData![0], count: Int(source.frameLength))) }
    let converter = AVAudioConverter(from: file.processingFormat, to: target)!
    let capacity = AVAudioFrameCount(Double(source.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
    let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
    var fed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return source
    }
    if let error { throw error }
    return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
}

func now() -> Double { CFAbsoluteTimeGetCurrent() }

protocol Bench {
    var name: String { get }
    func load() async throws
    func run(_ samples: [Float]) async throws -> String
}

final class ParakeetBench: Bench, @unchecked Sendable {
    let name = "Parakeet TDT 0.6b v3 (FluidAudio)"
    var manager: AsrManager?
    func load() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }
    func run(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make()
        return try await manager!.transcribe(samples, decoderState: &state).text
    }
}

final class WhisperBench: Bench, @unchecked Sendable {
    let name = "Whisper large-v3 turbo (WhisperKit)"
    let model: String
    var kit: WhisperKit?
    init(model: String) { self.model = model }
    func load() async throws {
        kit = try await WhisperKit(WhisperKitConfig(model: model, verbose: false, logLevel: .error, prewarm: true, load: true, download: true))
    }
    func run(_ samples: [Float]) async throws -> String {
        let options = DecodingOptions(task: .transcribe, language: "en", temperature: 0, withoutTimestamps: true)
        let results: [TranscriptionResult] = try await kit!.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }
}

final class AppleBench: Bench, @unchecked Sendable {
    let name = "Apple SFSpeechRecognizer (on-device)"
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    func load() async throws {
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else { throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "speech recognition not authorized (\(status.rawValue))"]) }
    }
    func run(_ samples: [Float]) async throws -> String {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.append(buffer)
        request.endAudio()
        return try await withCheckedThrowingContinuation { c in
            var done = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !done else { return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if let error { done = true; c.resume(throwing: error) }
            }
        }
    }
}

let args = CommandLine.arguments.dropFirst()
let dir = URL(fileURLWithPath: args.first ?? "clips")
let wanted = Set(args.dropFirst().isEmpty ? ["parakeet", "whisper", "apple"] : Array(args.dropFirst()))
let whisperModel = ProcessInfo.processInfo.environment["WHISPER_MODEL"] ?? "openai_whisper-large-v3-v20240930_turbo"

var clips: [Clip] = []
for line in try String(contentsOf: dir.appendingPathComponent("refs.tsv"), encoding: .utf8).split(separator: "\n") {
    let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
    clips.append(Clip(name: parts[0], voice: parts[1], reference: parts[2],
                      samples: try loadSamples(dir.appendingPathComponent("\(parts[0]).wav"))))
}
let extras = (ProcessInfo.processInfo.environment["EXTRA_WAVS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }

var benches: [Bench] = []
if wanted.contains("parakeet") { benches.append(ParakeetBench()) }
if wanted.contains("whisper") { benches.append(WhisperBench(model: whisperModel)) }
if wanted.contains("apple") { benches.append(AppleBench()) }

for bench in benches {
    print("\n## \(bench.name)\n")
    let loadStart = now()
    do { try await bench.load() } catch { print("load failed: \(error.localizedDescription)"); continue }
    let loadSeconds = now() - loadStart
    _ = try? await bench.run(clips[0].samples) // warm-up, not counted
    print("| clip | voice | audio s | latency ms | RTFx | WER | hypothesis |")
    print("|---|---|---|---|---|---|---|")
    var latencies: [Double] = []
    var errors = 0.0, words = 0.0, audio = 0.0
    for clip in clips {
        let start = now()
        let text = (try? await bench.run(clip.samples)) ?? "<error>"
        let ms = (now() - start) * 1000
        let wer = TranscriptMetrics.wordErrorRate(reference: clip.reference, hypothesis: text)
        let refWords = Double(TranscriptMetrics.normalizedWords(clip.reference).count)
        errors += wer * refWords; words += refWords; audio += clip.seconds
        latencies.append(ms)
        print(String(format: "| %@ | %@ | %.1f | %.0f | %.0f | %.1f%% | %@ |", clip.name, clip.voice, clip.seconds, ms,
                     clip.seconds * 1000 / ms, wer * 100, text.replacingOccurrences(of: "|", with: "/")))
    }
    for url in extras {
        guard let samples = try? loadSamples(url) else { continue }
        let start = now()
        let text = (try? await bench.run(samples)) ?? "<error>"
        print(String(format: "| %@ (real speech) | - | %.1f | %.0f | - | - | %@ |", url.lastPathComponent, Double(samples.count) / 16_000, (now() - start) * 1000, text))
    }
    let sorted = latencies.sorted()
    print(String(format: "\n**Summary:** load %.1f s (includes first download), median latency %.0f ms, p90 %.0f ms, total RTFx %.0f, WER %.2f%%",
                 loadSeconds, sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.9)],
                 audio * 1000 / latencies.reduce(0, +), errors / words * 100))
}
