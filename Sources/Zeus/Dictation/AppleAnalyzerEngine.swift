import AVFoundation
import Foundation
import Speech
import ZeusCore

/// Apple's SpeechAnalyzer with SpeechTranscriber (macOS 26 and later): the newer on-device
/// model behind Notes and Voice Memos. macOS downloads and keeps its language assets; ZEUS only
/// asks for them. On older systems it reports `.needsNewerMacOS` and is never used.
final class AppleAnalyzerEngine: TranscriptionEngine, @unchecked Sendable {
    let kind = TranscriptionEngineKind.appleAnalyzer
    private let lock = NSLock()
    private var progress: Double?

    static var isSupportedOS: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    func availability() async -> EngineAvailability {
        guard #available(macOS 26, *) else { return .needsNewerMacOS }
        if let fraction = lock.withLock({ progress }) { return .downloading(fraction) }
        guard SpeechTranscriber.isAvailable else { return .unavailable("Not supported on this Mac.") }
        guard let transcriber = await Self.transcriber(language: nil) else {
            return .unavailable("Your Mac's language is not supported yet.")
        }
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .ready
        case .downloading: return .downloading(0)
        case .supported: return .notDownloaded
        default: return .unavailable("Your Mac's language is not supported yet.")
        }
    }

    func prepare(progress report: (@Sendable (Double) -> Void)?) async throws {
        guard #available(macOS 26, *) else { throw TranscriptionError.notReady(kind) }
        guard let transcriber = await Self.transcriber(language: nil) else { throw TranscriptionError.notReady(kind) }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        lock.withLock { progress = 0 }
        defer { lock.withLock { progress = nil } }
        let observation = request.progress.observe(\.fractionCompleted) { [weak self] value, _ in
            let fraction = value.fractionCompleted
            self?.lock.withLock { self?.progress = fraction }
            report?(fraction)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        report?(1)
    }

    func transcribe(samples: [Float], hints: [String], language: String?) async throws -> String {
        guard !samples.isEmpty else { throw TranscriptionError.noSpeech }
        guard #available(macOS 26, *) else { throw TranscriptionError.notReady(kind) }
        guard let transcriber = await Self.transcriber(language: language) else { throw TranscriptionError.notReady(kind) }
        let wav = try TemporaryWAV.write(samples)
        defer { try? FileManager.default.removeItem(at: wav) }
        let collector = Task { () throws -> String in
            var parts: [String] = []
            for try await result in transcriber.results where result.isFinal {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
        }
        do {
            let context = AnalysisContext()
            if !hints.isEmpty { context.contextualStrings[.general] = Array(hints.prefix(100)) }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.setContext(context)
            let file = try AVAudioFile(forReading: wav)
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A transcriber for `language` (or the Mac's language), when Apple supports it.
    @available(macOS 26, *)
    private static func transcriber(language: String?) async -> SpeechTranscriber? {
        let wanted = language.map(Locale.init(identifier:)) ?? .current
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { return nil }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }
}
