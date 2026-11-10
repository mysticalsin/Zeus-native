import Foundation

/// Per-answer timing for voice.log (QA21). Injectable clock for unit tests.
public enum VoiceAnswerLatency {
    nonisolated(unsafe) public static var clock: () -> Date = { Date() }

    nonisolated(unsafe) private static var turnStarted: Date?
    nonisolated(unsafe) private static var firstSentenceAt: Date?

    public static func beginTurn(at date: Date? = nil) {
        turnStarted = date ?? clock()
        firstSentenceAt = nil
    }

    public static func noteFirstSentence(at date: Date? = nil) {
        if firstSentenceAt == nil { firstSentenceAt = date ?? clock() }
    }

    /// A speech-start figure larger than this is a stale clock, not a real delay (R24 logged 287 s).
    public static let maxPlausibleMs = 15_000

    /// Milliseconds from the first speakable sentence to when audio is ready to play.
    /// Nil when the clock is missing, negative, or too large to be this answer.
    public static func speechStartMs(speechBegan: Date? = nil) -> Int? {
        guard let first = firstSentenceAt else { return nil }
        let end = speechBegan ?? clock()
        let ms = Int((end.timeIntervalSince(first) * 1000).rounded())
        guard ms >= 0, ms <= maxPlausibleMs else { return nil }
        return ms
    }

    /// Reads the speech-start figure once, then forgets the sentence time so a later utterance
    /// cannot inherit it.
    public static func consumeSpeechStartMs(speechBegan: Date? = nil) -> Int? {
        let ms = speechStartMs(speechBegan: speechBegan)
        firstSentenceAt = nil
        return ms
    }

    public static func reset() {
        turnStarted = nil
        firstSentenceAt = nil
    }
}
