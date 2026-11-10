import Foundation
import Testing

/// QA19/QA21 merge guard: one untitled voice card (page heading is "Voice") plus "Speech to text"; no split provider cards.
@Suite struct SettingsVoiceCardContractTests {
    private static let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zeus/Settings/GSVoiceCards.swift")

    @Test func voiceSettingsUsesUntitledVoiceCardAndSpeechToTextOnly() throws {
        let text = try String(contentsOf: Self.sourceURL, encoding: .utf8)
        let titles = Self.gsCardTitles(in: text)
        #expect(titles == ["Speech to text"])
        #expect(text.contains("GSCard {"), "voice rows belong in one untitled card under GSPageHeading")
        #expect(!text.contains("GSCard(\"Voice\")"), "Voice section title must not repeat the page heading")
    }

    @Test func voiceSettingsDoesNotSplitUltronZeusAndKokoroCards() throws {
        let text = try String(contentsOf: Self.sourceURL, encoding: .utf8)
        let forbidden = [
            "Ultron voice",
            "Voice provider",
            "Zeus\u{2019}s voice",
            "GSCard(\"ElevenLabs\")",
            "GSCard(\"Kokoro\")",
            "GSCard(\"OpenAI-compatible TTS\")",
        ]
        for fragment in forbidden {
            #expect(!text.contains(fragment), "found forbidden voice card fragment: \(fragment)")
        }
    }

    private static func gsCardTitles(in source: String) -> [String] {
        let pattern = #"GSCard\("([^"]+)"\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[r])
        }
    }
}
