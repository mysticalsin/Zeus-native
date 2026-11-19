import Foundation
import Observation
import ZeusCore

/// Settings > Voice > Test voice: speaks a fixed Ultron line in English and in French through the same path
/// as a real answer and shows the time to first audio, the engine, the model and the voice.
@MainActor
@Observable
final class VoiceTestModel {
    static let shared = VoiceTestModel()

    struct Row: Identifiable, Equatable {
        let id = UUID()
        let language: String
        let engine: String
        let model: String
        let voice: String
        let firstAudioMs: Int?
        let verdict: String

        var summary: String {
            let time = firstAudioMs.map { "\($0) ms to first audio" } ?? "no audio"
            return "\(language): \(time), \(engine), model \(model), voice \(voice). \(verdict)"
        }
    }

    static let lines: [(language: String, text: String)] = [
        ("English", "Good evening, Tony. Everything is in order, and I am ready when you are."),
        ("French", "Bonsoir, Tony. Tout est en ordre, et je suis prêt quand vous l'êtes."),
    ]

    private(set) var rows: [Row] = []
    private(set) var running = false

    func run(speaker: Speaker) {
        guard !running else { return }
        running = true
        rows = []
        Task {
            for line in Self.lines {
                speaker.stop()
                let (stream, continuation) = AsyncStream<String>.makeStream()
                continuation.yield(line.text)
                continuation.finish()
                let outcome = await speaker.speak(sentenceStream: stream)
                rows.append(Row(language: line.language, engine: outcome.engine, model: speaker.modelDescription(engine: outcome.engine),
                                voice: outcome.voice.isEmpty ? "-" : outcome.voice, firstAudioMs: outcome.firstAudioMs,
                                verdict: outcome.firstAudioMs.map(VoiceLatencyTargets.voiceLegVerdict) ?? "nothing played"))
            }
            running = false
        }
    }
}
