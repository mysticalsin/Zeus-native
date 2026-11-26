import Foundation

/// Tip-exact `stt-latency` and `stt-failure` details for voice.log.
///
/// The packaged flush writes both lines for any generation above zero.
/// A cancel during open used to refuse the write, so a cold run and five warm
/// runs left voice.log with neither line. Generation zero is still not a turn.
public enum STTFlushLines {
    public static let talkHold = "talk-hold"
    public static let murmurTap = "murmur-tap"
    public static let latencyStage = "stt-latency"
    public static let failureStage = "stt-failure"

    /// `none` when text landed or this turn was not counting Apple text.
    /// `aborted` when the turn was cancelled. `no_text` when it ended empty.
    public static func failureWord(cancelled: Bool, textLanded: Bool) -> String {
        if cancelled { return "aborted" }
        if textLanded { return "none" }
        return "no_text"
    }

    /// Both voice.log details, or nil when no turn was armed.
    /// `cancelled` does not suppress the lines. It only chooses the failure word
    /// when the caller passes that word in `failure`.
    public static func details(generation: Int, cancelled: Bool, path: String,
                               keyDown: String = "0", captureStart: String = "-",
                               speechStart: String = "-", silenceDetected: String = "-",
                               endpointFired: String = "-", modelReady: String = "-",
                               firstPartial: String = "-", finalTranscript: String = "-",
                               deliveredToUI: String = "-", failure: String,
                               attempts: Int, failedTurns: Int) -> [STTVoiceLogLine]? {
        guard generation > 0 else { return nil }
        _ = cancelled
        let latency = [
            "path=\(path) key_down=\(keyDown)",
            "capture: capture_start=\(captureStart)",
            "vad: speech_start=\(speechStart) silence_detected=\(silenceDetected) endpoint_fired=\(endpointFired)",
            "asr: model_ready=\(modelReady) first_partial=\(firstPartial) final_transcript=\(finalTranscript)",
            "delivery: delivered_to_ui=\(deliveredToUI)",
            "failure=\(failure)",
        ].joined(separator: " | ")
        let rate = attempts > 0 ? Double(failedTurns) / Double(attempts) : 0
        let failureLine = "failure_rate path=\(path) attempts=\(attempts) failed_turns=\(failedTurns) rate=\(String(format: "%.3f", rate))"
        return [
            STTVoiceLogLine(stage: latencyStage, detail: latency),
            STTVoiceLogLine(stage: failureStage, detail: failureLine),
        ]
    }
}

public struct STTVoiceLogLine: Equatable, Sendable {
    public let stage: String
    public let detail: String

    public init(stage: String, detail: String) {
        self.stage = stage
        self.detail = detail
    }
}
