import Foundation

/// OpenAI shuts down its `POST /v1/audio/speech` models on 2027-01-06 and no newer model uses that endpoint
/// (source: OpenAI deprecations page and text-to-speech guide, read 2026-11-18). Zeus retires OpenAI speech
/// instead of migrating: from the shutdown instant no request is built, and speech falls to the next engine.
/// Pure: the caller passes the clock.
public enum OpenAISpeechRetirement {
    /// 2027-01-06T00:00:00Z.
    public static let shutdownDate = Date(timeIntervalSince1970: 1_799_193_600)

    static let retiringModels: Set<String> = [
        "tts-1", "tts-1-hd", "gpt-4o-mini-tts", "gpt-4o-mini-tts-2025-03-20", "gpt-4o-mini-tts-2025-12-15",
    ]
    static let retiringPrefixes = ["tts-1", "gpt-4o-mini-tts"]

    public static let endedNote = "Ended January 6, 2027"
    public static let upcomingNote = "OpenAI ends these voices on January 6, 2027. Zeus will switch to your next voice then."

    public static func isRetiringModel(_ model: String) -> Bool {
        retiringModels.contains(model) || retiringPrefixes.contains { model.hasPrefix($0) }
    }

    /// True for a deprecated speech model at or after the shutdown instant.
    public static func isRetired(model: String, at now: Date) -> Bool {
        now >= shutdownDate && isRetiringModel(model)
    }

    /// The one plain note for the OpenAI voice row: the heads-up before the date, "Ended" after it, nothing for a model
    /// this policy does not cover.
    public static func settingsNote(model: String, at now: Date) -> String? {
        guard isRetiringModel(model) else { return nil }
        return now >= shutdownDate ? endedNote : upcomingNote
    }
}
