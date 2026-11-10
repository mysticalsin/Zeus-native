import Foundation

/// Representative podcast and interview lines for O20 false-trigger checks (text-only, no playback).
public enum WakeFalseTriggerFixtures {
    public static let podcastLines: [String] = [
        "So the host asked about productivity tools and whether voice assistants help.",
        "They mentioned Greek mythology and the pantheon of gods without naming any product.",
        "The guest said the juice industry is cold pressed now and margins are tight.",
        "A zest of lemon on the fish was the chef's only flourish.",
        "Jesus is a common name in many cultures and not a wake phrase here.",
        "Zeus was king of the gods in ancient stories told on this episode.",
        "Hey there listeners, welcome back to another hour of tech news.",
        "I tried Zoom and Slack for calls but kept the mic muted most of the time.",
        "The algorithm suggested Spotify playlists with jazz and lo-fi beats.",
        "Open source models on Ollama run locally without sending audio to the cloud.",
        "She said hey Jesus was her neighbor and they carpool on Tuesdays.",
        "Deus ex machina is a plot device, not something you shout at your Mac.",
        "We ordered cold brew and talked about screen recording permissions.",
        "The transcript says open calculator but nobody was talking to an assistant.",
        "Ultron appears in fiction; this show never wakes a voice agent on purpose.",
        "Double tap and hold gestures on iPhones are unrelated to dictation keys.",
        "They debated whether AI should read answers aloud during meetings.",
        "Portuguese and English code switching happened but no wake word appeared.",
        "The podcast ran ten minutes of ads without anyone saying the assistant name.",
        "Closing remarks thanked sponsors and said see you next week.",
    ]

    /// Returns lines that incorrectly matched `WakePhrase.spot`. Expect zero for O20.
    public static func falseTriggers(in lines: [String] = podcastLines) -> [String] {
        lines.filter { WakePhrase.spot($0) != nil }
    }
}
