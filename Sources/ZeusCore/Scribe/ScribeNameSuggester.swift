import Foundation

/// A name Zeus thinks a speaker may have. It is only ever a suggestion: nothing renames itself, the owner taps
/// Accept (or types something else).
public struct ScribeNameSuggestion: Equatable, Sendable {
    public enum Evidence: Equatable, Sendable {
        /// The speaker said who they are ("I'm Marie", "this is Paul from finance", "Marie here").
        case introduction
        /// Someone else addressed the next speaker by name ("thanks, Marie", "over to you Paul").
        case address
    }

    public let speaker: ScribeSpeaker
    /// The attendee's or saved voice's full name when one matches, else the name as it was said.
    public let name: String
    public let evidence: Evidence
    /// Higher is stronger: an introduction counts 2, an address 1, summed over the meeting.
    public let score: Int
}

/// Pure, no network. Looks for names in what people say and keeps one only when it is backed up: it matches an
/// attendee on the invite or a saved voice, or the same speaker and name turn up at least twice.
public enum ScribeNameSuggester {
    /// Words that follow "I'm" or "this is" but are not names.
    static let notNames: Set<String> = [
        "i'm", "i’m", "i'll", "i've", "we're", "we'll", "sorry", "good", "great", "fine", "happy", "glad", "sure", "not", "just", "here", "there", "going", "calling",
        "looking", "back", "ready", "afraid", "late", "early", "still", "also", "now", "the", "a", "an", "it", "that",
        "this", "what", "why", "how", "so", "very", "really", "okay", "ok", "yes", "no", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march", "april", "may",
        "june", "july", "august", "september", "october", "november", "december", "thanks", "thank", "hello", "hi",
        "hey", "right", "over", "down", "up", "out", "come", "waiting", "well", "sir", "madam", "guys", "everyone", "everybody", "team", "all", "folks", "you", "we", "they",
    ]

    private static let capitalisedName = #"([A-Z][\p{L}'’-]{1,24})"#
    private static let introductions: [NSRegularExpression] = [
        #"(?i:\bi'm|\bi am|\bmy name is|\bthis is|\bit's|\bit is)\s+"# + capitalisedName,
        capitalisedName + #"\s+(?i:here|speaking)\b"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }
    private static let addresses: [NSRegularExpression] = [
        #"(?i:\bthanks|\bthank you|\bover to you|\bgo ahead|\bwelcome|\bhi|\bhello|\bhey|\bwhat do you think)[,.]?\s+"# + capitalisedName,
        capitalisedName + #"[,]\s+(?i:what do you think|over to you|can you|could you|would you|do you)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// - Parameters:
    ///   - segments: the meeting's final segments, in order.
    ///   - attendees: display names from the calendar invite (never emails).
    ///   - savedNames: names of voices the owner saved.
    ///   - ownerName: the owner's own name (About you); it is never suggested for a voice that is not the microphone's.
    public static func suggestions(
        segments: [ScribeTranscriptSegment],
        attendees: [String] = [],
        savedNames: [String] = [],
        ownerName: String? = nil
    ) -> [ScribeNameSuggestion] {
        let known = ScribeAttendeeNames.clean(attendees) + ScribeAttendeeNames.clean(savedNames)
        let ownerFirst = ownerName.flatMap { firstToken($0) }
        let finals = segments.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        struct Key: Hashable { let speaker: ScribeSpeaker; let name: String }
        var score: [Key: Int] = [:]
        var events: [Key: Int] = [:]
        var evidence: [Key: ScribeNameSuggestion.Evidence] = [:]
        var order: [Key] = []
        func note(_ key: Key, points: Int, kind: ScribeNameSuggestion.Evidence) {
            if score[key] == nil { order.append(key) }
            score[key, default: 0] += points
            events[key, default: 0] += 1
            if evidence[key] == nil || kind == .introduction { evidence[key] = kind }
        }

        for (index, segment) in finals.enumerated() {
            for candidate in captures(introductions, in: segment.text) {
                note(Key(speaker: segment.speaker, name: candidate), points: 2, kind: .introduction)
            }
            guard let next = finals[(index + 1)...].first(where: { $0.speaker != segment.speaker }) else { continue }
            for candidate in captures(addresses, in: segment.text) {
                note(Key(speaker: next.speaker, name: candidate), points: 1, kind: .address)
            }
        }

        var results: [ScribeNameSuggestion] = []
        for key in order {
            guard isUnnamed(key.speaker), let points = score[key] else { continue }
            let attendee = fullName(matching: key.name, in: known)
            // An invite or saved voice vouches for the name; otherwise it must have come up twice.
            guard attendee != nil || (events[key] ?? 0) >= 2 else { continue }
            if let ownerFirst, norm(key.name) == ownerFirst, key.speaker != .you { continue }
            results.append(ScribeNameSuggestion(
                speaker: key.speaker, name: attendee ?? key.name,
                evidence: evidence[key] ?? .address, score: points + (attendee == nil ? 0 : 1)
            ))
        }

        // One name per speaker, one speaker per name: the strongest claim wins, ties go to the earlier one.
        let ranked = results.enumerated().sorted { lhs, rhs in
            lhs.element.score != rhs.element.score ? lhs.element.score > rhs.element.score : lhs.offset < rhs.offset
        }
        var speakers: Set<ScribeSpeaker> = []
        var names: Set<String> = []
        var kept: [(offset: Int, suggestion: ScribeNameSuggestion)] = []
        for item in ranked {
            let nameKey = ScribeSpeakerNames.key(item.element.name)
            guard !speakers.contains(item.element.speaker), !names.contains(nameKey) else { continue }
            speakers.insert(item.element.speaker)
            names.insert(nameKey)
            kept.append((item.offset, item.element))
        }
        return kept.sorted { $0.offset < $1.offset }.map(\.suggestion)
    }

    /// Only a voice still called "Speaker N" (or unknown) is worth a suggestion; the microphone's "You" and a
    /// name someone already chose are left alone.
    static func isUnnamed(_ speaker: ScribeSpeaker) -> Bool {
        switch speaker {
        case .you: return false
        case .unknown: return true
        case .participant(let label):
            return label.hasPrefix("Speaker ") && Int(label.dropFirst("Speaker ".count)) != nil
        }
    }

    private static func captures(_ patterns: [NSRegularExpression], in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        var found: [String] = []
        for pattern in patterns {
            for match in pattern.matches(in: text, range: range) where match.numberOfRanges > 1 {
                guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
                let word = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
                if word.count >= 2, !notNames.contains(norm(word)) { found.append(word) }
            }
        }
        return found
    }

    /// The full display name of the attendee (or saved voice) whose first name or whole name is `word`.
    private static func fullName(matching word: String, in names: [String]) -> String? {
        let wanted = norm(word)
        return names.first { norm($0) == wanted || firstToken($0) == wanted }
    }

    private static func firstToken(_ name: String) -> String? {
        name.split(whereSeparator: \.isWhitespace).first.map { norm(String($0)) }
    }

    private static func norm(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
