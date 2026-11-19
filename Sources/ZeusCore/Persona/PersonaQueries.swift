import Foundation

/// Questions answered locally from the persona bank, without calling the brain.
public enum PersonaQueries {
    public static func localAnswer(for transcript: String) -> String? {
        localAnswer(for: transcript) { ZeusVoiceLines.line(for: $0) }
    }

    /// An explicit personality and owned line bank keep fixtures independent of saved preferences.
    public static func localAnswer(for transcript: String, personality: ZeusPersonality,
                                   lines: ZeusVoiceLines = ZeusVoiceLines()) -> String? {
        localAnswer(for: transcript) { lines.line(for: $0, personality: personality) }
    }

    private static func localAnswer(for transcript: String, line: (ZeusVoiceLines.Situation) -> String) -> String? {
        if let spoken = InstantTable.spokenAnswer(for: transcript) { return spoken }
        let key = Utterance(transcript).words.joined(separator: " ")
        guard !key.isEmpty else { return nil }

        if matchesIdentity(key) {
            return line(.identity)
        }
        if matchesMetaphysical(key) {
            return line(.metaphysical)
        }
        if matchesJoke(key) {
            return line(.joke)
        }
        if matchesComparison(key) {
            return line(.comparison)
        }
        if matchesSmallTalk(key) {
            return line(.smallTalk)
        }
        if key.contains("capital"), key.contains("australia") {
            return "Canberra. A planned city between Sydney and Melbourne, still standing."
        }
        if key.contains("capital"), key.contains("portugal") {
            return "Lisbon."
        }
        return nil
    }

    private static func matchesIdentity(_ key: String) -> Bool {
        ["who are you", "what are you", "introduce yourself"].contains { key.contains($0) }
    }

    private static func matchesMetaphysical(_ key: String) -> Bool {
        let cues = [
            "are you conscious", "are you alive", "are you real", "are you sentient",
            "are you a person", "are you human", "are you a human", "do you have a soul",
            "can you feel", "you conscious", "you alive", "you sentient", "real person",
        ]
        return cues.contains { key.contains($0) }
    }

    private static func matchesJoke(_ key: String) -> Bool {
        (key.contains("funny") && key.contains("monday")) || key.contains("tell me a joke") || key == "joke" || key.contains("make me laugh") || key.contains("say a joke")
    }

    private static func matchesComparison(_ key: String) -> Bool {
        ["smarter than me", "smarter than i am", "cleverer than me", "more intelligent than me", "better than me"]
            .contains { key.contains($0) }
    }

    private static func matchesSmallTalk(_ key: String) -> Bool {
        if key.contains("how are you") || key.contains("how's your day") || key.contains("how is your day") {
            return true
        }
        if key.contains("monday") && (key.contains("hate") || key.contains("dread") || key.contains("why")) {
            return true
        }
        return false
    }
}
