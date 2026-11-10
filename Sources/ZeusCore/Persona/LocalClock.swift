import Foundation

/// "What time is it" answered from the clock, with no model call.
/// The wall time is the system time zone. A Persian (or any other) calendar must not change the hour.
public enum LocalClock {
    /// Phrases that mean the clock on the wall, and nothing else ("what time is the meeting" stays on the brain).
    public static func isTimeQuestion(_ transcript: String) -> Bool {
        let key = normalized(transcript)
        return exact.contains(key)
    }

    /// "It's 12:39 AM." Hour 0 and 12 are both "12". Inject `now` and `timeZone` in tests.
    public static func spoken(now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let hour24 = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "AM" : "PM"
        return String(format: "It's %d:%02d %@.", hour12, minute, suffix)
    }

    public static func answer(for transcript: String, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard isTimeQuestion(transcript) else { return nil }
        return spoken(now: now, timeZone: timeZone)
    }

    private static let exact: Set<String> = [
        "what time is it",
        "what time is it right now",
        "what time is it now",
        "what is the time",
        "what is the time right now",
        "what is the time now",
        "tell me the time",
        "tell me what time it is",
        "do you have the time",
        "have you got the time",
        "current time",
    ]

    private static func normalized(_ transcript: String) -> String {
        var text = transcript.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        text = text.replacingOccurrences(of: "what's", with: "what is")
        text = text.replacingOccurrences(of: "whats", with: "what is")
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
        var index = 0
        let filler: Set<String> = ["hey", "hi", "ok", "okay", "zeus", "please", "um", "uh"]
        while index < words.count, filler.contains(words[index]) { index += 1 }
        return words[index...].joined(separator: " ")
    }
}
