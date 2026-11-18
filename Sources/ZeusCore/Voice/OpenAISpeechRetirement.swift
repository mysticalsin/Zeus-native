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

    public static let endedNote = "Ended January 6, 2027"
    public static let upcomingNote = "OpenAI ends these voices on January 6, 2027. Zeus will switch to your next voice then."
    static let openAIHost = "api.openai.com"

    /// Exactly the five ids OpenAI lists as shutting down. Any other id is left alone.
    public static func isRetiringModel(_ model: String) -> Bool { retiringModels.contains(model) }

    /// Only OpenAI's own endpoint shuts down. Nil or empty is the default base URL, which is OpenAI's; a custom
    /// OpenAI-compatible server (or an unparsable one) keeps working.
    public static func isOpenAIBase(_ baseURL: String?) -> Bool {
        guard let baseURL, !baseURL.isEmpty else { return true }
        return URL(string: baseURL)?.host?.lowercased() == openAIHost
    }

    /// True for a listed speech model on OpenAI's endpoint at or after the shutdown instant.
    public static func isRetired(model: String, baseURL: String? = nil, at now: Date) -> Bool {
        now >= shutdownDate && isRetiringModel(model) && isOpenAIBase(baseURL)
    }

    /// The one plain note for the OpenAI rows: the heads-up before the date, "Ended" after it, nothing for a model or
    /// server this policy does not cover.
    public static func settingsNote(model: String, baseURL: String? = nil, at now: Date) -> String? {
        guard isRetiringModel(model), isOpenAIBase(baseURL) else { return nil }
        return now >= shutdownDate ? endedNote : upcomingNote
    }

    /// Shown when the saved engine choice is OpenAI after the shutdown: the choice is kept, `effective` is what speaks.
    public static func endedChoiceLine(choice: UltronEngineChoice, retired: Bool, effective: String) -> String? {
        guard retired, case .fixed(.openAI) = choice else { return nil }
        return "OpenAI voices ended. Zeus uses \(effective)."
    }
}
