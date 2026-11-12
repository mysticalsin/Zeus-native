import Foundation

/// Original voice design for the cloud engines. Qualities only: deep baritone, calm, precise diction,
/// a faint synthetic sheen, measured pacing, dry wit, a hint of grandeur. No real person or film is named.
public enum UltronCloudVoice {
    public static let openAIModel = "gpt-4o-mini-tts"
    /// The deepest stock OpenAI voice.
    public static let openAIVoice = "onyx"

    public static let openAIInstructions = """
    Voice: a deep baritone, calm and precise, with a faint synthetic sheen. Pacing: measured and \
    unhurried, with a short pause before the key word. Tone: quietly confident and courteous, dry wit \
    delivered straight, a hint of grandeur but never theatrical or hostile. Crisp, clean diction.
    """

    /// Only the gpt-4o family accepts `instructions`; tts-1 style models reject it.
    public static func supportsInstructions(model: String) -> Bool {
        model.lowercased().contains("gpt-4o")
    }

    /// ElevenLabs delivery for the designed or stock voice: some range, a little style, unhurried.
    public static let elevenLabsSettings: [String: Double] = [
        "stability": 0.35, "similarity_boost": 0.8, "style": 0.3, "speed": 0.95,
    ]

    /// Kokoro: a deep male voice, slowed.
    public static let kokoroVoice = "am_michael"
    public static let kokoroSpeed = 0.88
}
