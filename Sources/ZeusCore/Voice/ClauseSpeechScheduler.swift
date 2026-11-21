import Foundation

/// An injected clock. Tests advance it inside the synthesizer, so the first schedule
/// can be compared with the moment the whole reply finishes rendering.
public struct SpeechManualClock: Equatable, Sendable {
    public var seconds: Double

    public init(seconds: Double = 0) { self.seconds = seconds }

    public mutating func advance(by interval: Double) {
        if interval > 0 { seconds += interval }
    }
}

/// Proposed warm-Kokoro budget for the first 40–90 character clause on an M-series Mac.
/// This is not a Mac measurement. The Linux harness times the number it actually got.
public enum ClauseSpeechBudget {
    public static let proposedFirstClauseSeconds = 1.0
}

public struct ClauseScheduleReceipt: Equatable, Sendable {
    public var chunks: [String]
    public var firstScheduledAt: Double
    public var fullRenderCompletedAt: Double
    public var scheduled: Int
}

/// Speaks `SpeechClauseChunker` pieces through a `SpeechOutputProcessing` seam.
/// Each piece is synthesized, shaped, and scheduled before the next piece is rendered.
/// A later cancel drops that piece and does not schedule a tail.
public enum ClauseSpeechScheduler {
    /// Silence between clauses, about a comma's pause, so the join is not a smear.
    public static let clausePauseSeconds = 0.090
    public static let edgeFadeSeconds = 0.010

    public static func speak(
        text: String,
        sampleRate: Double,
        clock: inout SpeechManualClock,
        output: any SpeechOutputProcessing,
        token: SpeechCancelToken? = nil,
        synthesize: (String, inout SpeechManualClock) -> [Float],
        schedule: ([Float], Double) -> Void
    ) -> ClauseScheduleReceipt {
        let chunks = SpeechClauseChunker.chunks(of: text)
        var firstScheduledAt: Double?
        var scheduled = 0
        for (index, chunk) in chunks.enumerated() {
            if token?.isCancelled == true { break }
            let raw = synthesize(chunk, &clock)
            // The clause that was cancelled while it rendered is not scheduled, and nothing is appended after it.
            if token?.isCancelled == true { break }
            var shaped = output.process(raw, sampleRate: sampleRate)
            if chunks.count > 1 {
                if index + 1 < chunks.count {
                    shaped = fadeOutAndPause(shaped, sampleRate: sampleRate)
                } else {
                    shaped = fadeIn(shaped, sampleRate: sampleRate)
                }
            }
            let at = clock.seconds
            schedule(shaped, at)
            if firstScheduledAt == nil { firstScheduledAt = at }
            scheduled += 1
        }
        return ClauseScheduleReceipt(
            chunks: chunks,
            firstScheduledAt: firstScheduledAt ?? clock.seconds,
            fullRenderCompletedAt: clock.seconds,
            scheduled: scheduled)
    }

    private static func fadeOutAndPause(_ samples: [Float], sampleRate: Double) -> [Float] {
        var output = samples
        let fade = min(output.count, max(1, Int((sampleRate * edgeFadeSeconds).rounded())))
        if fade > 1 {
            let start = output.count - fade
            for index in 0..<fade {
                let theta = Double(index) / Double(fade - 1) * Double.pi / 2
                output[start + index] *= Float(cos(theta))
            }
        }
        let pause = max(0, Int((sampleRate * clausePauseSeconds).rounded()))
        if pause > 0 { output.append(contentsOf: [Float](repeating: 0, count: pause)) }
        return output
    }

    private static func fadeIn(_ samples: [Float], sampleRate: Double) -> [Float] {
        var output = samples
        let fade = min(output.count, max(1, Int((sampleRate * edgeFadeSeconds).rounded())))
        guard fade > 1 else { return output }
        for index in 0..<fade {
            let theta = Double(index) / Double(fade - 1) * Double.pi / 2
            output[index] *= Float(sin(theta))
        }
        return output
    }
}
