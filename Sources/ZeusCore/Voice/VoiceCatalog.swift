import Foundation

/// One selectable provider voice: the id sent to the API, the label shown in Settings, a short tone note.
public struct CatalogVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let detail: String
    public var title: String { id.prefix(1).uppercased() + id.dropFirst() }
    public init(_ id: String, _ detail: String) { self.id = id; self.detail = detail }
}

/// The public voice names of the OpenAI speech endpoint (Settings > Voice picker, writes `voice.openai.voice`).
/// Source: https://developers.openai.com/api/docs/guides/text-to-speech ("Voice options", read 2026-11-16).
/// gpt-4o-mini-tts takes all 13; tts-1 and tts-1-hd take the smaller legacy set.
/// Those models are listed there as shutting down on 2027-01-06.
public enum OpenAIVoiceCatalog {
    public static let voices: [CatalogVoice] = [
        CatalogVoice("alloy", "Neutral"), CatalogVoice("ash", "Warm"), CatalogVoice("ballad", "Expressive"),
        CatalogVoice("cedar", "Natural, recommended"), CatalogVoice("coral", "Friendly"), CatalogVoice("echo", "Calm"),
        CatalogVoice("fable", "Storyteller"), CatalogVoice("marin", "Natural, recommended"), CatalogVoice("nova", "Bright"),
        CatalogVoice("onyx", "Deep"), CatalogVoice("sage", "Measured"), CatalogVoice("shimmer", "Soft"),
        CatalogVoice("verse", "Versatile"),
    ]

    /// What `tts-1` and `tts-1-hd` accept.
    static let legacyIDs: Set<String> = ["alloy", "ash", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer"]

    public static func voices(forModel model: String) -> [CatalogVoice] {
        model.hasPrefix("tts-1") ? voices.filter { legacyIDs.contains($0.id) } : voices
    }

    /// The picker list at `now`: empty once OpenAI has shut the model down, so retired voices are not offered.
    public static func voices(forModel model: String, baseURL: String? = nil, at now: Date) -> [CatalogVoice] {
        OpenAISpeechRetirement.isRetired(model: model, baseURL: baseURL, at: now) ? [] : voices(forModel: model)
    }
}

/// The 30 prebuilt Gemini TTS voices (writes `voice.gemini.voice`).
/// Source: https://ai.google.dev/gemini-api/docs/speech-generation (redirects to aistudio.google.com/docs/speech-generation),
/// "Prebuilt voices", read 2026-11-16. The tone notes are the page's own one-word labels.
public enum GeminiVoiceCatalog {
    public static let defaultVoice = "Kore"

    public static let voices: [CatalogVoice] = [
        CatalogVoice("Achernar", "Soft"), CatalogVoice("Achird", "Friendly"), CatalogVoice("Algenib", "Gravelly"),
        CatalogVoice("Algieba", "Smooth"), CatalogVoice("Alnilam", "Firm"), CatalogVoice("Aoede", "Breezy"),
        CatalogVoice("Autonoe", "Bright"), CatalogVoice("Callirrhoe", "Easy-going"), CatalogVoice("Charon", "Informative"),
        CatalogVoice("Despina", "Smooth"), CatalogVoice("Enceladus", "Breathy"), CatalogVoice("Erinome", "Clear"),
        CatalogVoice("Fenrir", "Excitable"), CatalogVoice("Gacrux", "Mature"), CatalogVoice("Iapetus", "Clear"),
        CatalogVoice("Kore", "Firm"), CatalogVoice("Laomedeia", "Upbeat"), CatalogVoice("Leda", "Youthful"),
        CatalogVoice("Orus", "Firm"), CatalogVoice("Puck", "Upbeat"), CatalogVoice("Pulcherrima", "Forward"),
        CatalogVoice("Rasalgethi", "Informative"), CatalogVoice("Sadachbia", "Lively"), CatalogVoice("Sadaltager", "Knowledgeable"),
        CatalogVoice("Schedar", "Even"), CatalogVoice("Sulafat", "Warm"), CatalogVoice("Umbriel", "Easy-going"),
        CatalogVoice("Vindemiatrix", "Gentle"), CatalogVoice("Zephyr", "Bright"), CatalogVoice("Zubenelgenubi", "Casual"),
    ]

    /// A stored name that is one of the 30 (matched without regard to case), else the default.
    public static func resolve(stored: String?) -> String {
        guard let stored else { return defaultVoice }
        return voices.first { $0.id.caseInsensitiveCompare(stored) == .orderedSame }?.id ?? defaultVoice
    }
}

/// The one original sentence every voice preview speaks, rendered with the owner's own key. Nothing is bundled.
public enum VoiceCatalogPreview {
    public static let sentence = "Hello, this is how I sound. Tell me what you would like to do next."
}
