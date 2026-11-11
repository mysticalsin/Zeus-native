import Foundation
import ZeusCore

/// Gives an offline speech model (Parakeet) a live feel: audio is cut at pauses by `ChunkScheduler`
/// while the key is held, each finished chunk is transcribed in the background, and on release only
/// the tail is left to do. The decisions live in ZeusCore; this class only moves audio and tasks.
final class IncrementalTranscriptionStream: TranscriptionStream, @unchecked Sendable {
    private let engine: any TranscriptionEngine
    private let hints: [String]
    private let language: String?
    private let lock = NSLock()
    private var scheduler = ChunkScheduler()
    private var samples: [Float] = []
    private var jobs: [Task<String, Error>] = []
    private var closed = false
    private var cancelled = false

    init(engine: any TranscriptionEngine, hints: [String], language: String?) {
        self.engine = engine
        self.hints = hints
        self.language = language
    }

    func send(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            guard !closed, !cancelled else { return }
            samples += chunk
            for range in scheduler.append(chunk) { enqueueLocked(range) }
        }
    }

    /// Starts one chunk after the one before it finishes, so the model never runs two at once.
    /// Callers hold `lock`.
    private func enqueueLocked(_ range: Range<Int>) {
        let slice = Array(samples[range])
        let previous = jobs.last
        let engine = engine, hints = hints, language = language
        jobs.append(Task(priority: .userInitiated) {
            _ = await previous?.result
            try Task.checkCancellation()
            return try await engine.transcribe(samples: slice, hints: hints, language: language)
        })
    }

    func finish() async throws -> String {
        let started = Date()
        let (decision, queued, everything, chunksBeforeTail) = lock.withLock { () -> (TailDecision, [Task<String, Error>], [Float], Int) in
            closed = true
            let before = jobs.count
            let decision = scheduler.finalDecision()
            if case .transcribeTail(let range) = decision { enqueueLocked(range) }
            return (decision, jobs, samples, before)
        }
        var parts: [String] = []
        var failed = false
        for job in queued {
            switch await job.result {
            case .success(let text): parts.append(text)
            case .failure: failed = true
            }
        }
        if lock.withLock({ cancelled }) || Task.isCancelled { throw CancellationError() }
        let text: String
        if failed, !everything.isEmpty {
            // One chunk failed: the whole recording goes through once, so nothing is lost.
            text = try await engine.transcribe(samples: everything, hints: hints, language: language)
        } else {
            text = ChunkTranscriptJoiner.join(parts)
        }
        let tailSeconds: Double
        if case .transcribeTail(let range) = decision { tailSeconds = Double(range.count) / 16_000 } else { tailSeconds = 0 }
        NSLog("[ZEUS] dictation: finalize %d ms (chunks before release %d, tail %.1f s, %@)",
              DictationLatency.milliseconds(from: started, to: Date()), chunksBeforeTail, tailSeconds,
              failed ? "retried whole recording" : "tail only")
        return text
    }

    func cancel() {
        let running = lock.withLock { () -> [Task<String, Error>] in
            cancelled = true
            closed = true
            defer { jobs = []; samples = [] }
            return jobs
        }
        running.forEach { $0.cancel() }
    }
}
