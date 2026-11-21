import Foundation

/// One talk turn's stage times, in milliseconds. A pure value: nothing here opens a
/// session, reads a clock, or places a call.
public struct TalkLatencySample: Equatable, Sendable {
    public var sttFinalMs: Int
    /// Time until capture was ready. Absent capture is not a stage of first audio.
    public var captureReadyMs: Int?
    public var firstTokenMs: Int
    public var ttsFirstMs: Int
    /// Speech-to-text final, first token, and first speech audio. Capture is not added.
    public var firstAudioMs: Int { sttFinalMs + firstTokenMs + ttsFirstMs }
    public var firstVisualMs: Int?

    public init(sttFinalMs: Int, captureReadyMs: Int? = nil, firstTokenMs: Int, ttsFirstMs: Int, firstVisualMs: Int? = nil) {
        self.sttFinalMs = sttFinalMs
        self.captureReadyMs = captureReadyMs
        self.firstTokenMs = firstTokenMs
        self.ttsFirstMs = ttsFirstMs
        self.firstVisualMs = firstVisualMs
    }
}

/// Targets for a talk turn. The 8 s first-text budget stays on `FastTier` and is not edited here.
public enum TalkLatencyBudget {
    /// Key-up to the first audio buffer.
    public static let firstAudioTargetMs = 1_200
    /// How long key-up may wait for a speech-to-text final.
    public static let sttFinalCapMs = 450
}
