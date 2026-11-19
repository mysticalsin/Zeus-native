import Foundation
import ZeusCore

/// Collects the stage times of the voice turn in flight and writes one `[ZEUS] voice-latency ...` line when
/// it ends (also appended to voice.log, which `scripts/voice-latency.sh` reads). The line holds numbers and
/// engine names only: no transcript, no answer text, no key.
@MainActor
final class VoiceLatency {
    static let shared = VoiceLatency()

    private var trace: VoiceLatencyTrace?
    private var origin: ContinuousClock.Instant?
    private var watchdog: Task<Void, Never>?
    /// The most recent finished turn, for the Settings "Test voice" panel and tests.
    private(set) var last: VoiceLatencyTrace?

    private func elapsedMs() -> Int {
        guard let origin else { return 0 }
        let d = ContinuousClock.now - origin
        return max(0, Int(d.components.seconds) * 1000 + Int(d.components.attoseconds / 1_000_000_000_000_000))
    }

    /// Key-up (or the transcript, for a wake or typed turn) is time zero. An unfinished earlier trace is written first.
    func begin(at instant: ContinuousClock.Instant = .now) {
        finish()
        trace = VoiceLatencyTrace()
        origin = instant
    }

    var isActive: Bool { trace != nil }

    func mark(_ stage: VoiceStage) {
        guard trace != nil else { return }
        let now = elapsedMs()
        trace?.mark(stage, atMs: now)
    }

    func setBrain(engine: String, model: String) {
        trace?.brainEngine = engine
        trace?.model = model
    }

    func setSpeech(engine: String, voice: String, model: String?, reason: String, effectPercent: Int) {
        guard trace?.ttsEngine == "-" else { return }
        trace?.ttsEngine = model.map { "\(engine)/\($0)" } ?? engine
        trace?.voice = voice
        trace?.reason = reason
        trace?.effectPercent = effectPercent
    }

    /// The reply was handed over; the turn ends when the speaker goes quiet, or after 45 s at the latest.
    func finishWhenQuiet(isSpeaking: @escaping @MainActor () -> Bool) {
        watchdog?.cancel()
        let started = ContinuousClock.now
        watchdog = Task { @MainActor [weak self] in
            while isSpeaking(), ContinuousClock.now - started < .seconds(45), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func finish() {
        watchdog?.cancel()
        watchdog = nil
        guard var finished = trace else { return }
        trace = nil
        finished.mark(.turnEnd, atMs: elapsedMs())
        origin = nil
        last = finished
        // Turns that never reached the speaker (an instant action, an error) have nothing to time.
        guard finished.ms(.requestSent) != nil || finished.ms(.firstAudio) != nil else { return }
        let detail = finished.logDetail
        NSLog("[ZEUS] voice-latency %@", detail)
        VoiceLog.log("voice-latency", detail, mirror: false)
    }
}
